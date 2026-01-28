from fastapi import FastAPI, Form
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from typing import List, Optional, Dict, Any, Callable, Pattern
import spacy
from collections import defaultdict
from dateparser import parse
from datetime import datetime, timedelta
import re
import calendar
from dateutil.relativedelta import relativedelta
import requests
import math

# --- helper: haversine distance in meters ---
def haversine(lat1, lon1, lat2, lon2):
    R = 6371000  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)

    a = math.sin(dphi/2)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

# --- OSM enrichment ---
def enrich_location_with_osm(text: str) -> dict:
    url = "https://nominatim.openstreetmap.org/search"
    params = {
        "q": text,
        "format": "json",
        "addressdetails": 1,
        "limit": 1,
    }
    headers = {
        "User-Agent": "YourAppName/1.0 (your@email.com)"
    }

    resp = requests.get(url, params=params, headers=headers, timeout=5)
    resp.raise_for_status()

    data = resp.json()
    if not data:
        return {"text": text}

    item = data[0]
    address = item.get("address", {})

    # boundingbox processing
    boundingbox = [float(x) for x in item.get("boundingbox", [None, None, None, None])]
    if all(boundingbox):
        south, north, west, east = boundingbox
        radius = haversine(south, west, north, east) / 2
        searchradius = radius + 10 * (radius ** (3/5))

        # --- compute searcharea as expanded bounding box ---
        center_lat = (north + south) / 2
        center_lon = (east + west) / 2

        # Current half-width and half-height in meters
        lat_distance = haversine(center_lat, center_lon, north, center_lon)
        lon_distance = haversine(center_lat, center_lon, center_lat, east)
        max_distance = max(lat_distance, lon_distance)

        # Scale factor to reach searchradius
        scale = searchradius / max_distance if max_distance else 1

        # Compute new lat/lon deltas
        delta_lat = (north - south) / 2 * scale
        delta_lon = (east - west) / 2 * scale

        searcharea = [
            center_lat - delta_lat,  # south
            center_lat + delta_lat,  # north
            center_lon - delta_lon,  # west
            center_lon + delta_lon   # east
        ]
    else:
        radius = None
        searchradius = None
        searcharea = None

    return {
        "text": text,
        "country": address.get("country"),
        "state": (
            address.get("state")
            or address.get("region")
            or address.get("province")
        ),
        "city": (
            address.get("city")
            or address.get("town")
            or address.get("village")
        ),
        "coordinates": {
            "latitude": float(item["lat"]) if "lat" in item else None,
            "longitude": float(item["lon"]) if "lon" in item else None,
            "boundingbox": boundingbox if all(boundingbox) else None,
            "radius": radius,
            "searchradius": searchradius,
            "searcharea": searcharea
        },
    }

# --- Pydantic models ---
class DateEntity(BaseModel):
    text: str
    range: bool
    date: Optional[str] = None
    start_date: Optional[str] = None
    end_date: Optional[str] = None

class SentenceEntities(BaseModel):
    text: str
    entities: Optional[Dict[str, List[Any]]] = None

    class Config:
        exclude_none = True

class SearchQueryAnalyzerRequest(BaseModel):
    text: str
    week_start_sunday: bool = False
    period_end_mode_current: bool = False
    last_as_previous: bool = False

class SearchQueryAnalyzerResponse(BaseModel):
    result: List[Dict[str, Any]]

# --- Rule processor type ---
RuleProcessor = Callable[[str], tuple[bool, Optional[str], Optional[str], Optional[str]]]

class DateRule:
    def __init__(self, pattern: str | Pattern, processor: RuleProcessor):
        self.pattern = re.compile(pattern, re.IGNORECASE) if isinstance(pattern, str) else pattern
        self.processor = processor

# --- Main analyzer class ---
class SearchQueryAnalyzer:
    FACILITY_LABELS = {"FAC", "GPE", "LOC", "ORG"}

    SECTION_CONTEXT = "context"
    SECTION_DATES = "dates"
    SECTION_PERSONS = "persons"
    SECTION_LOCATIONS = "locations"
    SECTION_TYPES = "types"

    FILE_TYPE_KEYWORDS = {
        "image": ["image", "images", "picture", "pictures", "photo", "photos"],
        "video": ["video", "videos", "film", "films", "movie", "movies", "cartoon", "cartoons", "animation", "animations"]
    }

    FILE_TYPE_KEYWORDS_FLAT = set(k for keywords in FILE_TYPE_KEYWORDS.values() for k in keywords)

    def __init__(self):
        self.nlp = spacy.load("en_core_web_md")
        self.date_rules = self._build_date_rules()

    # ---------- helpers ----------
    @staticmethod
    def subtract_months(dt, months):
        return dt - relativedelta(months=months)

    @staticmethod
    def subtract_years(dt, years):
        return dt - relativedelta(years=years)

    @staticmethod
    def subtract_weeks(dt, weeks):
        return dt - timedelta(weeks=weeks)

    @staticmethod
    def subtract_days(dt, days):
        return dt - timedelta(days=days)

    # ---------- week/month/year helpers ----------
    def get_week_start_end(self, reference: datetime, which: str):
        weekday = reference.weekday()
        if self.week_start_sunday:
            weekday = (weekday + 1) % 7

        if which == "this":
            start = reference - timedelta(days=weekday)
            end = reference if self.period_end_mode_current else start + timedelta(days=6)
        elif which == "last":
            if self.last_as_previous:
                start, end = self.get_week_start_end(reference, "previous")
            else:
                start = reference - timedelta(days=7)
                end = reference
        elif which == "next":
            start = reference + timedelta(days=(7 - weekday))
            end = start + timedelta(days=6)
        elif which == "previous":
            start = reference - timedelta(days=weekday + 7)
            end = start + timedelta(days=6)

        return start, end

    def get_month_start_end(self, reference: datetime, which: str):
        if which == "this":
            start = reference.replace(day=1)
            end = (
                reference
                if self.period_end_mode_current
                else reference.replace(day=calendar.monthrange(reference.year, reference.month)[1])
            )
        elif which == "last":
            if self.last_as_previous:
                start, end = self.get_month_start_end(reference, "previous")
            else:
                start = self.subtract_months(reference, 1)
                end = reference
        elif which == "next":
            next_month = 1 if reference.month == 12 else reference.month + 1
            next_year = reference.year + 1 if reference.month == 12 else reference.year
            start = datetime(next_year, next_month, 1)
            end = start.replace(day=calendar.monthrange(start.year, start.month)[1])
        elif which == "previous":
            last_month_date = reference.replace(day=1) - timedelta(days=1)
            start = last_month_date.replace(day=1)
            end = start.replace(day=calendar.monthrange(start.year, start.month)[1])

        return start, end

    def get_year_start_end(self, reference: datetime, which: str):
        if which == "this":
            start = datetime(reference.year, 1, 1)
            end = reference if self.period_end_mode_current else datetime(reference.year, 12, 31)
        elif which == "last":
            if self.last_as_previous:
                start, end = self.get_year_start_end(reference, "previous")
            else:
                start = self.subtract_years(reference, 1)
                end = reference
        elif which == "next":
            start = datetime(reference.year + 1, 1, 1)
            end = datetime(reference.year + 1, 12, 31)
        elif which == "previous":
            start = datetime(reference.year - 1, 1, 1)
            end = datetime(reference.year - 1, 12, 31)

        return start, end

    # ---------- rule processors ----------
    def single_relative_day(self, text: str, now: datetime):
        parsed = parse(text, settings={"RELATIVE_BASE": now, "PREFER_DATES_FROM": "past"})
        if parsed:
            return False, parsed.date().isoformat(), None, None
        return False, None, None, None

    def last_week_rule(self, text: str, now: datetime):
        start, end = self.get_week_start_end(now, "last")
        return True, None, start.date().isoformat(), end.date().isoformat()

    def this_week_rule(self, text: str, now: datetime):
        start, end = self.get_week_start_end(now, "this")
        return True, None, start.date().isoformat(), end.date().isoformat()

    def last_month_rule(self, text: str, now: datetime):
        start, end = self.get_month_start_end(now, "last")
        return True, None, start.date().isoformat(), end.date().isoformat()

    def this_month_rule(self, text: str, now: datetime):
        start, end = self.get_month_start_end(now, "this")
        return True, None, start.date().isoformat(), end.date().isoformat()

    def last_year_rule(self, text: str, now: datetime):
        start, end = self.get_year_start_end(now, "last")
        return True, None, start.date().isoformat(), end.date().isoformat()

    def this_year_rule(self, text: str, now: datetime):
        start, end = self.get_year_start_end(now, "this")
        return True, None, start.date().isoformat(), end.date().isoformat()

    def last_n_generic(self, text: str, n: int, unit: str, now: datetime):
        if unit == "days":
            start = self.subtract_days(now, n)
        elif unit == "weeks":
            start = self.subtract_weeks(now, n)
        elif unit == "months":
            start = self.subtract_months(now, n)
        elif unit == "years":
            start = self.subtract_years(now, n)
        else:
            return False, None, None, None

        return True, None, start.date().isoformat(), now.date().isoformat()

    def past_n_generic(self, text: str, n: int, unit: str, now: datetime):
        if unit == "days":
            start = self.subtract_days(now, n)
            end = now
        elif unit == "weeks":
            start, _ = self.get_week_start_end(now, "previous")
            end = start + timedelta(weeks=n) - timedelta(days=1)
        elif unit == "months":
            start = self.subtract_months(now.replace(day=1), n)
            end = start.replace(day=calendar.monthrange(start.year, start.month)[1])
        elif unit == "years":
            start = datetime(now.year - n, 1, 1)
            end = datetime(now.year - n, 12, 31)
        else:
            return False, None, None, None

        return True, None, start.date().isoformat(), end.date().isoformat()

    # ---------- build registry ----------
    def _build_date_rules(self):
        return [
            DateRule(r"yesterday|today|tomorrow|a year ago|three months ago",
                     lambda t: self.single_relative_day(t, self.now)),
            DateRule(r"last week", lambda t: self.last_week_rule(t, self.now)),
            DateRule(r"this week", lambda t: self.this_week_rule(t, self.now)),
            DateRule(r"last month", lambda t: self.last_month_rule(t, self.now)),
            DateRule(r"this month", lambda t: self.this_month_rule(t, self.now)),
            DateRule(r"last year", lambda t: self.last_year_rule(t, self.now)),
            DateRule(r"this year", lambda t: self.this_year_rule(t, self.now)),
            DateRule(r"last (\d+) (days|weeks|months|years)",
                     lambda t: self.last_n_generic(
                         t,
                         int(re.search(r'\d+', t).group()),
                         re.search(r"(days|weeks|months|years)", t).group(1),
                         self.now)),
            DateRule(r"(past|previous) (\d+) (days|weeks|months|years)",
                     lambda t: self.past_n_generic(
                         t,
                         int(re.search(r'\d+', t).group()),
                         re.search(r"(days|weeks|months|years)", t).group(3),
                         self.now)),
            DateRule(r"(past|previous) (week|month|year)",
                     lambda t: self.past_n_generic(t, 1, t.split()[1] + "s", self.now)),
        ]

    # ---------- parse date using registry ----------
    def parse_relative_date_registry(self, text: str):
        for rule in self.date_rules:
            if rule.pattern.search(text):
                return rule.processor(text)

        parsed = parse(text, settings={"RELATIVE_BASE": self.now, "PREFER_DATES_FROM": "past"})
        if not parsed:
            return False, None, None, None

        text_clean = text.strip()

        if re.match(r"[A-Za-z]+\s\d{4}$", text_clean):
            start = parsed.replace(day=1)
            end = parsed.replace(day=calendar.monthrange(parsed.year, parsed.month)[1])
            return True, None, start.date().isoformat(), end.date().isoformat()

        if re.match(r"\d{4}$", text_clean):
            return True, None, f"{parsed.year}-01-01", f"{parsed.year}-12-31"

        if re.match(r"^[A-Za-z]+$", text_clean):
            year = self.now.year - (parsed.month > self.now.month)
            start = datetime(year, parsed.month, 1)
            end = datetime(year, parsed.month, calendar.monthrange(year, parsed.month)[1])
            return True, None, start.date().isoformat(), end.date().isoformat()

        return False, parsed.date().isoformat(), None, None

    # ---------- main analyze method ----------
    def analyze(self, request: SearchQueryAnalyzerRequest) -> SearchQueryAnalyzerResponse:
        self.now = datetime.now()
        self.week_start_sunday = request.week_start_sunday
        self.period_end_mode_current = request.period_end_mode_current
        self.last_as_previous = request.last_as_previous

        doc = self.nlp(request.text)
        result_per_sentence = []

        for sent in doc.sents:
            result = defaultdict(list)

            for ent in sent.ents:
                if ent.label_ == "PERSON":
                    result[self.SECTION_PERSONS].append(ent.text)

                elif ent.label_ in {"GPE", "LOC", "FAC"}:
                    result[self.SECTION_LOCATIONS].append(
                        enrich_location_with_osm(ent.text)
                    )

                if ent.label_ in self.FACILITY_LABELS:
                    clean = ent.text[4:] if ent.text.lower().startswith("the ") else ent.text
                    if clean.lower() not in self.FILE_TYPE_KEYWORDS_FLAT:
                        result[self.SECTION_CONTEXT].append(clean)

                elif ent.label_ == "DATE":
                    text = ent.text
                    range_matches = re.findall(
                        r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}'
                        r'|[A-Za-z]+\s\d{1,2},\s\d{4}'
                        r'|[A-Za-z]+\s\d{4})',
                        text
                    )

                    if len(range_matches) >= 2 and re.search(r'\b(to|–|-)\b', text):
                        ps, pe = parse(range_matches[0]), parse(range_matches[1])
                        if ps and pe:
                            range_flag = True
                            date = None
                            start_date = ps.strftime("%Y-%m-%d")
                            end_date = pe.strftime("%Y-%m-%d")
                        else:
                            range_flag, date, start_date, end_date = False, None, None, None
                    else:
                        range_flag, date, start_date, end_date = self.parse_relative_date_registry(text)
                        if not range_flag and date:
                            start_date = end_date = date
                        elif range_flag:
                            date = None

                    result[self.SECTION_DATES].append({
                        "text": text,
                        "range": range_flag,
                        **({"date": date} if date else {}),
                        "start_date": start_date,
                        "end_date": end_date
                    })

            entity_token_idxs = {i for ent in sent.ents for i in range(ent.start, ent.end)}
            for token in sent:
                if token.i not in entity_token_idxs and token.pos_ in ("NOUN", "VERB", "PROPN"):
                    if token.text.lower() not in self.FILE_TYPE_KEYWORDS_FLAT:
                        result[self.SECTION_CONTEXT].append(token.text)

            types_set = set()
            for token in sent:
                t = token.text.lower()
                for type_name, keywords in self.FILE_TYPE_KEYWORDS.items():
                    if t in keywords:
                        types_set.add(type_name)
            if types_set:
                result[self.SECTION_TYPES] = list(types_set)

            sentence_dict = {"text": sent.text.strip()}
            cleaned = {k: v for k, v in result.items() if v}
            if cleaned:
                sentence_dict["entities"] = cleaned

            result_per_sentence.append(sentence_dict)

        return SearchQueryAnalyzerResponse(result=result_per_sentence)

# --- FastAPI setup ---
#app = FastAPI(title="NER Sentence Analyzer")

def declare_endpoints(app):
    @app.post("/analyze", response_model=SearchQueryAnalyzerResponse)
    def analyze_endpoint(request: SearchQueryAnalyzerRequest):
        analyzer = SearchQueryAnalyzer()
        return analyzer.analyze(request)

    # --- /test endpoint ---
    @app.get("/test", response_class=HTMLResponse)
    def test_form():
        default_text = "Photos of riding horses near the Eiffel Tower and Taj Mahal with John Smith and Ann in May 2025."
        return f"""
        <!DOCTYPE html>
        <html>
        <head>
        <title>Search Query Analyzer Test</title>
        </head>
        <body>
        <h1>Search Query Analyzer Test Form</h1>
        <table>
        <form id="analyzeForm">
            <tr><td><label for="text">Search Query Text:</label></tr></td>
            <tr><td><textarea id="text" name="text" rows="5" cols="200">{default_text}</textarea></tr></td>

            <tr><td><input type="checkbox" id="week_start_sunday" name="week_start_sunday">
            <label for="week_start_sunday">Week starts from Sunday</label></tr></td>

            <tr><td><input type="checkbox" id="period_end_mode_current" name="period_end_mode_current">
            <label for="period_end_mode_current">Period end mode is "current"</label></tr></td>

            <tr><td><input type="checkbox" id="last_as_previous" name="last_as_previous">
            <label for="last_as_previous">Process "last" in the same way as "previous"</label></tr></td>

            <tr><td><button type="submit">Analyze</button></tr></td>
        </form>
        </table>

        <pre id="result" style="margin-top:30px; width:700px; white-space: pre-wrap;"></pre>

        <script>
            const form = document.getElementById('analyzeForm');
            form.addEventListener('submit', async (e) => {{
            e.preventDefault();

            const payload = {{
                text: document.getElementById('text').value,
                week_start_sunday: document.getElementById('week_start_sunday').checked,
                period_end_mode_current: document.getElementById('period_end_mode_current').checked,
                last_as_previous: document.getElementById('last_as_previous').checked
            }};

            const response = await fetch('/photos/analyzer/analyze', {{
                method: 'POST',
                headers: {{
                    'Content-Type': 'application/json'
                }},
                body: JSON.stringify(payload)
            }});

            const result = await response.json();
            document.getElementById('result').textContent = JSON.stringify(result, null, 4);
            }});
        </script>
        </body>
        </html>
        """

if __name__ == "__main__":
    import uvicorn
    app = FastAPI(title="NER Sentence Analyzer")
    declare_endpoints(app)
    uvicorn.run(app, host="0.0.0.0", port=8000)
