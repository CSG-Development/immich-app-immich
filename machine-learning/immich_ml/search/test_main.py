import pytest
from datetime import datetime
from server import (
    SearchQueryAnalyzer,
    SearchQueryAnalyzerRequest,
    SearchQueryAnalyzerResponse,
)

# ------------------------------------------------------------------
# Freeze time so relative dates are deterministic
# ------------------------------------------------------------------
FIXED_NOW = datetime(2026, 1, 14, 12, 0, 0)


@pytest.fixture
def analyzer(monkeypatch):
    class FixedDatetime(datetime):
        @classmethod
        def now(cls, tz=None):
            return FIXED_NOW

    monkeypatch.setattr("server.datetime", FixedDatetime)
    return SearchQueryAnalyzer()


# ------------------------------------------------------------------
# Test data: Requests + Expected Responses
# ------------------------------------------------------------------
TEST_DATA = [
#================================================================================
# GENERAL SECTION
#================================================================================
    (
        SearchQueryAnalyzerRequest(
            text="Photos of riding horses near the Eiffel Tower and Taj Mahal with John Smith and Ann in May 2025.",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Photos of riding horses near the Eiffel Tower and Taj Mahal with John Smith and Ann in May 2025.",
                    "entities": {
                        "context": [
                            "Eiffel Tower",
                            "Taj Mahal",
                            "riding",
                            "horses",
                        ],
                        "persons": [
                            "John Smith",
                            "Ann",
                        ],
                        "locations": [
                            {
                                "text": "the Eiffel Tower",
                                "country": "United States",
                                "state": "Tennessee",
                                "city": "Paris",
                                "coordinates": {
                                   "latitude": 36.2869515,
                                   "longitude": -88.3015211,
                                   "boundingbox": [
                                       36.2868913,
                                       36.2870222,
                                       -88.3016017,
                                       -88.3014397,
                                   ],
                                   "radius": 10.279747534039293,
                                   "searchradius": 50.75499094730315,
                                   "searcharea": [
                                       36.28650029940033,
                                       36.28741320059967,
                                       -88.30208559684604,
                                       -88.30095580315395,
                                   ],
                                },
                            },
                            {
                                "text": "Taj Mahal",
                                "country": "India",
                                "state": "Uttar Pradesh",
                                "city": "Agra",
                                "coordinates": {
                                   "latitude": 27.1750075,
                                   "longitude": 78.0421013,
                                   "boundingbox": [
                                       27.1745358,
                                       27.1754823,
                                       78.0415593,
                                       78.0426212,
                                   ],
                                   "radius": 74.34875589374715,
                                   "searchradius": 207.0161575590336,
                                   "searcharea": [
                                       27.17314730896733,
                                       27.17687079103267,
                                       78.04000152015045,
                                       78.04417897984955,
                                   ],
                                },
                            },
                        ],
                        "types": [
                            "image"
                        ],
                        "dates": [
                            {
                                "text": "May 2025",
                                "range": True,
                                "start_date": "2025-05-01",
                                "end_date": "2025-05-31",
                            }
                        ],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Subscription from March 1, 2025 to March 31, 2025.",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Subscription from March 1, 2025 to March 31, 2025.",
                    "entities": {
                        "dates": [
                            {
                                "text": "March 1, 2025 to March 31, 2025",
                                "range": True,
                                "start_date": "2025-03-01",
                                "end_date": "2025-03-31",
                            }
                        ],
                        "context": ["Subscription"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Sailing yesterday.",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Sailing yesterday.",
                    "entities": {
                        "dates": [
                            {
                                "text": "yesterday",
                                "range": False,
                                "date": "2026-01-13",
                                "start_date": "2026-01-13",
                                "end_date": "2026-01-13",
                            }
                        ],
                        "context": ["Sailing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Cooking this year.",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Cooking this year.",
                    "entities": {
                        "dates": [
                            {
                                "text": "this year",
                                "range": True,
                                "start_date": "2026-01-01",
                                "end_date": "2026-12-31",
                            }
                        ],
                        "context": ["Cooking"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Swimming this week.",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Swimming this week.",
                    "entities": {
                        "dates": [
                            {
                                "text": "this week",
                                "range": True,
                                "start_date": "2026-01-12",
                                "end_date": "2026-01-18",
                            }
                        ],
                        "context": ["Swimming"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Hiking last month",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Hiking last month",
                    "entities": {
                        "dates": [
                            {
                                "text": "last month",
                                "range": True,
                                "start_date": "2025-12-14",
                                "end_date": "2026-01-14",
                            }
                        ],
                        "context": ["Hiking"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Hunting previous month",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Hunting previous month",
                    "entities": {
                        "dates": [
                            {
                                "text": "previous month",
                                "range": True,
                                "start_date": "2025-12-01",
                                "end_date": "2025-12-31",
                            }
                        ],
                        "context": ["Hunting"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Hunting past month",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Hunting past month",
                    "entities": {
                        "dates": [
                            {
                                "text": "past month",
                                "range": True,
                                "start_date": "2025-12-01",
                                "end_date": "2025-12-31",
                            }
                        ],
                        "context": ["Hunting"],
                    },
                }
            ]
        ),
    ),
#================================================================================
# DATE SECTION
#================================================================================
#----------------------------------------
# Today, yesterday, tomorrow
#----------------------------------------
    (
        SearchQueryAnalyzerRequest(
            text="Testing today",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing today",
                    "entities": {
                        "dates": [
                            {
                                "text": "today",
                                "range": False,
                                "date": "2026-01-14",
                                "start_date": "2026-01-14",
                                "end_date": "2026-01-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing yesterday",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing yesterday",
                    "entities": {
                        "dates": [
                            {
                                "text": "yesterday",
                                "range": False,
                                "date": "2026-01-13",
                                "start_date": "2026-01-13",
                                "end_date": "2026-01-13",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing tomorrow",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing tomorrow",
                    "entities": {
                        "dates": [
                            {
                                "text": "tomorrow",
                                "range": False,
                                "date": "2026-01-15",
                                "start_date": "2026-01-15",
                                "end_date": "2026-01-15",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
#----------------------------------------
# A day/week/month/year ago
#----------------------------------------
    (
        SearchQueryAnalyzerRequest(
            text="Testing a day ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing a day ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "a day ago",
                                "range": False,
                                "date": "2026-01-13",
                                "start_date": "2026-01-13",
                                "end_date": "2026-01-13",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing a week ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing a week ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "a week ago",
                                "range": False,
                                "date": "2026-01-07",
                                "start_date": "2026-01-07",
                                "end_date": "2026-01-07",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing a month ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing a month ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "a month ago",
                                "range": False,
                                "date": "2025-12-14",
                                "start_date": "2025-12-14",
                                "end_date": "2025-12-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing a year ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing a year ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "a year ago",
                                "range": False,
                                "date": "2025-01-14",
                                "start_date": "2025-01-14",
                                "end_date": "2025-01-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
#----------------------------------------
# One day/week/month/year ago
#----------------------------------------
    (
        SearchQueryAnalyzerRequest(
            text="Testing one day ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing one day ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "one day ago",
                                "range": False,
                                "date": "2026-01-13",
                                "start_date": "2026-01-13",
                                "end_date": "2026-01-13",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing one week ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing one week ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "one week ago",
                                "range": False,
                                "date": "2026-01-07",
                                "start_date": "2026-01-07",
                                "end_date": "2026-01-07",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing one month ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing one month ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "one month ago",
                                "range": False,
                                "date": "2025-12-14",
                                "start_date": "2025-12-14",
                                "end_date": "2025-12-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing one year ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing one year ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "one year ago",
                                "range": False,
                                "date": "2025-01-14",
                                "start_date": "2025-01-14",
                                "end_date": "2025-01-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
#----------------------------------------
# Two days/weeks/months/years ago
#----------------------------------------
    (
        SearchQueryAnalyzerRequest(
            text="Testing two days ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing two days ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "two days ago",
                                "range": False,
                                "date": "2026-01-12",
                                "start_date": "2026-01-12",
                                "end_date": "2026-01-12",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing two weeks ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing two weeks ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "two weeks ago",
                                "range": False,
                                "date": "2025-12-31",
                                "start_date": "2025-12-31",
                                "end_date": "2025-12-31",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing two months ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing two months ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "two months ago",
                                "range": False,
                                "date": "2025-11-14",
                                "start_date": "2025-11-14",
                                "end_date": "2025-11-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing two years ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing two years ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "two years ago",
                                "range": False,
                                "date": "2024-01-14",
                                "start_date": "2024-01-14",
                                "end_date": "2024-01-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
#----------------------------------------
# 3 days/weeks/months/years ago
#----------------------------------------
    (
        SearchQueryAnalyzerRequest(
            text="Testing 3 days ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing 3 days ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "3 days ago",
                                "range": False,
                                "date": "2026-01-11",
                                "start_date": "2026-01-11",
                                "end_date": "2026-01-11",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing 3 weeks ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing 3 weeks ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "3 weeks ago",
                                "range": False,
                                "date": "2025-12-24",
                                "start_date": "2025-12-24",
                                "end_date": "2025-12-24",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing 3 months ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing 3 months ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "3 months ago",
                                "range": False,
                                "date": "2025-10-14",
                                "start_date": "2025-10-14",
                                "end_date": "2025-10-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing 3 years ago",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing 3 years ago",
                    "entities": {
                        "dates": [
                            {
                                "text": "3 years ago",
                                "range": False,
                                "date": "2023-01-14",
                                "start_date": "2023-01-14",
                                "end_date": "2023-01-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
#----------------------------------------
# Last week/month/year
#----------------------------------------
    (
        SearchQueryAnalyzerRequest(
            text="Testing last week",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing last week",
                    "entities": {
                        "dates": [
                            {
                                "text": "last week",
                                "range": True,
                                "start_date": "2026-01-07",
                                "end_date": "2026-01-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing last month",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing last month",
                    "entities": {
                        "dates": [
                            {
                                "text": "last month",
                                "range": True,
                                "start_date": "2025-12-14",
                                "end_date": "2026-01-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing last year",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing last year",
                    "entities": {
                        "dates": [
                            {
                                "text": "last year",
                                "range": True,
                                "start_date": "2025-01-14",
                                "end_date": "2026-01-14",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
#----------------------------------------
# Previous week/month/year
#----------------------------------------
#    (
#        SearchQueryAnalyzerRequest(
#            text="Testing previous week",
#            week_start_sunday=False,
#            period_end_mode_current=False,
#            last_as_previous=False,
#        ),
#        SearchQueryAnalyzerResponse(
#            result=[
#                {
#                    "text": "Testing previous week",
#                    "entities": {
#                        "dates": [
#                            {
#                                "text": "previous week",
#                                "range": True,
#                                "start_date": "2026-01-05",
#                                "end_date": "2026-01-11",
#                            }
#                        ],
#                        "context": ["Testing"],
#                    },
#                }
#            ]
#        ),
#    ),
#    (
#        SearchQueryAnalyzerRequest(
#            text="Testing previous month",
#            week_start_sunday=False,
#            period_end_mode_current=False,
#            last_as_previous=False,
#        ),
#        SearchQueryAnalyzerResponse(
#            result=[
#                {
#                    "text": "Testing previous month",
#                    "entities": {
#                        "dates": [
#                            {
#                                "text": "previous month",
#                                "range": True,
#                                "start_date": "2025-12-01",
#                                "end_date": "2025-12-31",
#                            }
#                        ],
#                        "context": ["Testing"],
#                    },
#                }
#            ]
#        ),
#    ),
#    (
#        SearchQueryAnalyzerRequest(
#            text="Testing previous year",
#            week_start_sunday=False,
#            period_end_mode_current=False,
#            last_as_previous=False,
#        ),
#        SearchQueryAnalyzerResponse(
#            result=[
#                {
#                    "text": "Testing previous year",
#                    "entities": {
#                        "dates": [
#                            {
#                                "text": "previous year",
#                                "range": True,
#                                "start_date": "2025-01-01",
#                                "end_date": "2025-12-31",
#                            }
#                        ],
#                        "context": ["Testing"],
#                    },
#                }
#            ]
#        ),
#    ),
#----------------------------------------
# Past week/month/year
#----------------------------------------
#    (
#        SearchQueryAnalyzerRequest(
#            text="Testing past week",
#            week_start_sunday=False,
#            period_end_mode_current=False,
#            last_as_previous=False,
#        ),
#        SearchQueryAnalyzerResponse(
#            result=[
#                {
#                    "text": "Testing past week",
#                    "entities": {
#                        "dates": [
#                            {
#                                "text": "past week",
#                                "range": True,
#                                "start_date": "2026-01-05",
#                                "end_date": "2026-01-11",
#                            }
#                        ],
#                        "context": ["Testing"],
#                    },
#                }
#            ]
#        ),
#    ),
#    (
#        SearchQueryAnalyzerRequest(
#            text="Testing past month",
#            week_start_sunday=False,
#            period_end_mode_current=False,
#            last_as_previous=False,
#        ),
#        SearchQueryAnalyzerResponse(
#            result=[
#                {
#                    "text": "Testing past month",
#                    "entities": {
#                        "dates": [
#                            {
#                                "text": "past month",
#                                "range": True,
#                                "start_date": "2025-12-01",
#                                "end_date": "2025-12-31",
#                            }
#                        ],
#                        "context": ["Testing"],
#                    },
#                }
#            ]
#        ),
#    ),
#    (
#        SearchQueryAnalyzerRequest(
#            text="Testing past year",
#            week_start_sunday=False,
#            period_end_mode_current=False,
#            last_as_previous=False,
#        ),
#        SearchQueryAnalyzerResponse(
#            result=[
#                {
#                    "text": "Testing past year",
#                    "entities": {
#                        "dates": [
#                            {
#                                "text": "past year",
#                                "range": True,
#                                "start_date": "2025-01-01",
#                                "end_date": "2025-12-31",
#                            }
#                        ],
#                        "context": ["Testing"],
#                    },
#                }
#            ]
#        ),
#    ),
#----------------------------------------
# Months
#----------------------------------------
    (
        SearchQueryAnalyzerRequest(
            text="Testing May",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing May",
                    "entities": {
                        "dates": [
                            {
                                "text": "May",
                                "range": True,
                                "start_date": "2025-05-01",
                                "end_date": "2025-05-31",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing in October",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing in October",
                    "entities": {
                        "dates": [
                            {
                                "text": "October",
                                "range": True,
                                "start_date": "2025-10-01",
                                "end_date": "2025-10-31",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing in April",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing in April",
                    "entities": {
                        "dates": [
                            {
                                "text": "April",
                                "range": True,
                                "start_date": "2025-04-01",
                                "end_date": "2025-04-30",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing in February",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing in February",
                    "entities": {
                        "dates": [
                            {
                                "text": "February",
                                "range": True,
                                "start_date": "2025-02-01",
                                "end_date": "2025-02-28",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
#----------------------------------------
# Years
#----------------------------------------
#    (
#        SearchQueryAnalyzerRequest(
#            text="Testing in 2025",
#            week_start_sunday=False,
#            period_end_mode_current=False,
#            last_as_previous=False,
#        ),
#        SearchQueryAnalyzerResponse(
#            result=[
#                {
#                    "text": "Testing in 2025",
#                    "entities": {
#                        "dates": [
#                            {
#                                "text": "2025",
#                                "range": True,
#                                "start_date": "2025-01-01",
#                                "end_date": "2025-12-31",
#                            }
#                        ],
#                        "context": ["Testing"],
#                    },
#                }
#            ]
#        ),
#    ),
#    (
#        SearchQueryAnalyzerRequest(
#            text="Testing in 2025 year",
#            week_start_sunday=False,
#            period_end_mode_current=False,
#            last_as_previous=False,
#        ),
#        SearchQueryAnalyzerResponse(
#            result=[
#                {
#                    "text": "Testing in 2025 year",
#                    "entities": {
#                        "dates": [
#                            {
#                                "text": "2025 year",
#                                "range": True,
#                                "start_date": "2025-01-01",
#                                "end_date": "2025-12-31",
#                            }
#                        ],
#                        "context": ["Testing"],
#                    },
#                }
#            ]
#        ),
#    ),
#----------------------------------------
# Month + Year
#----------------------------------------
    (
        SearchQueryAnalyzerRequest(
            text="Testing in June 2020",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing in June 2020",
                    "entities": {
                        "dates": [
                            {
                                "text": "June 2020",
                                "range": True,
                                "start_date": "2020-06-01",
                                "end_date": "2020-06-30",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
    (
        SearchQueryAnalyzerRequest(
            text="Testing in February 2024",
            week_start_sunday=False,
            period_end_mode_current=False,
            last_as_previous=False,
        ),
        SearchQueryAnalyzerResponse(
            result=[
                {
                    "text": "Testing in February 2024",
                    "entities": {
                        "dates": [
                            {
                                "text": "February 2024",
                                "range": True,
                                "start_date": "2024-02-01",
                                "end_date": "2024-02-29",
                            }
                        ],
                        "context": ["Testing"],
                    },
                }
            ]
        ),
    ),
]


# ------------------------------------------------------------------
# Parametrized test
# ------------------------------------------------------------------
@pytest.mark.parametrize("analyzer_request, expected_response", TEST_DATA)
def test_search_query_analyzer_full_response(analyzer, analyzer_request, expected_response):
    actual_response = analyzer.analyze(analyzer_request)

    # Compare full response structure
    assert actual_response.model_dump(exclude_none=True) == expected_response.model_dump(
        exclude_none=True
    )
