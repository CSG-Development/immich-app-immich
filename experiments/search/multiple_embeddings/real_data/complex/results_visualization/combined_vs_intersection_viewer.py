import argparse
import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
import uvicorn


# ============================================================
# CONSTANTS
# ============================================================

BASE_DIR = Path(__file__).resolve().parent

DEFAULT_RESULTS = (
    BASE_DIR
    / "voc_similarity"
    / "combined_vs_individual.json"
)

DEFAULT_IMAGES_DIR = (
    BASE_DIR
    / "voc_subset"
    / "images"
)

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8000


# ============================================================
# GLOBALS
# ============================================================

RESULTS = {}
IMAGE_ITEMS = []

RESULTS_PATH = None
IMAGES_DIR = None

app = FastAPI()


# ============================================================
# LOGGING
# ============================================================

def log(message):
    print(
        f"[INFO] {message}",
        flush=True,
    )


def warning(message):
    print(
        f"[WARNING] {message}",
        flush=True,
    )


# ============================================================
# LOAD RESULTS
# ============================================================

def load_results(path):
    path = Path(path)

    if not path.exists():
        raise RuntimeError(
            f"Results file does not exist: {path}"
        )

    with path.open(
        "r",
        encoding="utf-8",
    ) as f:
        return json.load(f)


# ============================================================
# IMAGE PATH
# ============================================================

def find_image_path(
    images_dir,
    image_file,
):
    images_dir = Path(images_dir)

    candidates = [
        images_dir / image_file,
        images_dir / Path(image_file).name,
    ]

    for path in candidates:
        if path.exists() and path.is_file():
            return path

    filename = Path(
        image_file
    ).name

    matches = list(
        images_dir.rglob(filename)
    )

    if matches:
        return matches[0]

    return None


# ============================================================
# DIFFERENCE HELPERS
# ============================================================

def has_any_difference(
    comparison,
):
    difference = comparison.get(
        "difference",
        {},
    )

    return any(
        [
            difference.get(
                "max_cosine_difference",
                0,
            ) != 0,

            difference.get(
                "max_modified_similarity_difference",
                0,
            ) != 0,

            difference.get(
                "original_difference",
                False,
            ),

            difference.get(
                "squared_difference",
                False,
            ),

            difference.get(
                "segmented_original_difference",
                False,
            ),

            difference.get(
                "segmented_squared_difference",
                False,
            ),

            difference.get(
                "found_difference",
                False,
            ),

            difference.get(
                "better_difference",
                False,
            ),
        ]
    )


def has_found_difference(
    comparison,
):
    return comparison.get(
        "difference",
        {},
    ).get(
        "found_difference",
        False,
    )


# ============================================================
# BUILD IMAGE ITEMS
# ============================================================

def build_image_items(
    data,
):
    items = []

    for result in data.get(
        "results",
        [],
    ):
        comparisons = result.get(
            "comparisons",
            {},
        )

        if not comparisons:
            continue

        found_differences = 0
        total_differences = 0

        for comparison in comparisons.values():

            if has_any_difference(
                comparison
            ):
                total_differences += 1

            if has_found_difference(
                comparison
            ):
                found_differences += 1

        items.append(
            {
                "file": result.get(
                    "file"
                ),

                "source": result.get(
                    "source"
                ),

                "annotated_classes": result.get(
                    "annotated_classes",
                    [],
                ),

                "comparisons": comparisons,

                "num_comparisons": len(
                    comparisons
                ),

                "num_differences": (
                    total_differences
                ),

                "num_found_differences": (
                    found_differences
                ),
            }
        )

    return items


# ============================================================
# ROUTES
# ============================================================

@app.get(
    "/",
    response_class=HTMLResponse,
)
def index():
    return HTMLResponse(
        HTML_PAGE
    )


@app.get(
    "/api/data",
)
def api_data():
    return JSONResponse(
        {
            "results": IMAGE_ITEMS,
        }
    )


@app.get(
    "/api/image/{image_path:path}",
)
def api_image(image_path: str):
    image_file = find_image_path(
        IMAGES_DIR,
        image_path,
    )

    if image_file is None:
        return JSONResponse(
            {
                "error": (
                    f"Image not found: "
                    f"{image_path}"
                )
            },
            status_code=404,
        )

    return FileResponse(
        image_file
    )


# ============================================================
# HTML
# ============================================================

HTML_PAGE = r"""
<!DOCTYPE html>
<html lang="en">

<head>

<meta charset="UTF-8">

<meta
    name="viewport"
    content="width=device-width, initial-scale=1.0"
>

<title>
Combined vs Individual Viewer
</title>

<style>

* {
    box-sizing: border-box;
}

html,
body {
    margin: 0;
    padding: 0;
    width: 100%;
    height: 100%;
}

body {
    font-family:
        Arial,
        Helvetica,
        sans-serif;

    background: #f4f4f4;
    color: #222;

    overflow: hidden;
}


/* ============================================================
   HEADER
   ============================================================ */

#header {
    height: 76px;

    background: #ffffff;

    border-bottom: 1px solid #cfcfcf;

    display: flex;
    align-items: center;

    padding: 0 18px;

    gap: 18px;
}

#title {
    font-size: 20px;
    font-weight: 700;

    white-space: nowrap;
}

#fileName {
    font-size: 15px;

    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;

    flex: 1;
}

#navigation {
    display: flex;
    align-items: center;

    gap: 8px;
}

button {
    border: 1px solid #bcbcbc;

    background: #ffffff;

    padding: 7px 12px;

    border-radius: 4px;

    cursor: pointer;

    font-size: 13px;
}

button:hover {
    background: #eeeeee;
}

button:disabled {
    color: #999999;
    background: #f5f5f5;
    cursor: default;
}

#counter {
    min-width: 85px;

    text-align: center;

    font-size: 13px;
}


/* ============================================================
   FILTER BAR
   ============================================================ */

#filters {
    height: 52px;

    background: #ffffff;

    border-bottom: 1px solid #d0d0d0;

    display: flex;
    align-items: center;

    padding: 0 18px;

    gap: 18px;

    font-size: 13px;
}

.filter-group {
    display: flex;
    align-items: center;
    gap: 6px;
}

#stats {
    margin-left: auto;

    color: #555;

    white-space: nowrap;
}


/* ============================================================
   MAIN
   ============================================================ */

#main {
    height: calc(100vh - 128px);

    display: flex;

    overflow: hidden;
}


/* ============================================================
   IMAGE PANEL
   ============================================================ */

#imagePanel {
    width: 42%;

    min-width: 360px;

    background: #eeeeee;

    border-right: 1px solid #c7c7c7;

    padding: 18px;

    overflow: auto;

    display: flex;
    flex-direction: column;
}

#imageContainer {
    flex: 1;

    min-height: 0;

    display: flex;

    align-items: center;
    justify-content: center;

    overflow: hidden;
}

#mainImage {
    max-width: 100%;
    max-height: 100%;

    object-fit: contain;

    cursor: pointer;

    background: #ffffff;

    box-shadow:
        0 1px 4px rgba(0, 0, 0, 0.20);
}

#imageInfo {
    margin-top: 12px;

    font-size: 13px;

    background: #ffffff;

    border: 1px solid #d0d0d0;

    padding: 10px;

    border-radius: 4px;
}

#classes {
    margin-top: 5px;

    color: #444;
}


/* ============================================================
   RESULTS PANEL
   ============================================================ */

#resultsPanel {
    flex: 1;

    overflow: auto;

    padding: 14px 16px 30px 16px;

    background: #fafafa;
}


/* ============================================================
   QUERY CARD
   ============================================================ */

.queryCard {
    background: #ffffff;

    border: 1px solid #cfcfcf;

    border-radius: 5px;

    margin-bottom: 14px;

    overflow: hidden;
}

.queryCard.foundDifference {
    border-left: 5px solid #d47700;
}

.queryCard.anyDifference {
    border-left: 5px solid #777777;
}

.queryHeader {
    padding: 9px 12px;

    background: #f1f1f1;

    border-bottom: 1px solid #d0d0d0;

    display: flex;
    align-items: center;

    gap: 10px;
}

.queryName {
    font-size: 15px;
    font-weight: 700;

    flex: 1;
}

.queryClasses {
    color: #666;

    font-size: 12px;
}

.differenceBadge {
    padding: 3px 7px;

    border-radius: 3px;

    font-size: 11px;

    background: #e6e6e6;
}

.foundDifference .differenceBadge {
    background: #f3d4a8;
}


/* ============================================================
   COMPARISON
   ============================================================ */

.comparisonGrid {
    display: grid;

    grid-template-columns:
        minmax(250px, 1fr)
        minmax(300px, 1.2fr)
        minmax(230px, 0.9fr);

    /*
     * Stretch all three columns to the height of the
     * tallest column. This makes the vertical separators
     * continue through the entire Individual classes area.
     */
    align-items: stretch;
}

.comparisonColumn {
    padding: 12px;

    border-right: 1px solid #dedede;

    min-width: 0;
}

.comparisonColumn:last-child {
    border-right: none;
}

.columnTitle {
    font-size: 13px;
    font-weight: 700;

    margin-bottom: 9px;
}


/* ============================================================
   INDIVIDUAL RESULTS
   ============================================================ */

.individualDetails {
    margin-top: 14px;

    padding-top: 10px;

    border-top: 2px solid #bdbdbd;
}

.individualDetailsTitle {
    font-size: 12px;

    font-weight: 700;

    margin-bottom: 8px;
}

.individualResults {
    display: flex;

    flex-direction: column;

    gap: 8px;
}

.individualResult {
    border: 1px solid #dddddd;

    border-radius: 4px;

    background: #fafafa;

    overflow: hidden;
}

.individualResultTitle {
    padding: 6px 8px;

    background: #eeeeee;

    border-bottom: 1px solid #dddddd;

    font-size: 12px;

    font-weight: 700;
}

.individualResultBody {
    padding: 6px 8px;
}


/* ============================================================
   METRICS
   ============================================================ */

.metric {
    display: flex;

    align-items: center;

    justify-content: space-between;

    min-height: 26px;

    border-bottom: 1px solid #eeeeee;

    font-size: 12px;
}

.metric:last-child {
    border-bottom: none;
}

.metricName {
    color: #555;

    padding-right: 10px;
}

.metricValue {
    font-weight: 600;

    font-variant-numeric:
        tabular-nums;
}

.booleanTrue {
    color: #19722b;
}

.booleanFalse {
    color: #777;
}

.metricDiffPositive {
    color: #19722b;
}

.metricDiffNegative {
    color: #a12626;
}

.metricDiffZero {
    color: #777;
}


/* ============================================================
   FOUND BOX
   ============================================================ */

.foundBox {
    margin-top: 10px;

    padding: 7px 9px;

    border-radius: 4px;

    font-size: 12px;

    font-weight: 700;

    text-align: center;
}

.foundYes {
    background: #dcefdc;

    color: #236b2c;
}

.foundNo {
    background: #eeeeee;

    color: #666666;
}

.foundConflict {
    background: #f5d8ad;

    color: #8a4d00;
}


/* ============================================================
   EMPTY
   ============================================================ */

#empty {
    height: 100%;

    display: flex;

    align-items: center;
    justify-content: center;

    color: #777;

    font-size: 16px;
}


/* ============================================================
   FULLSCREEN
   ============================================================ */

#fullscreen {
    display: none;

    position: fixed;

    z-index: 1000;

    left: 0;
    top: 0;
    right: 0;
    bottom: 0;

    background: rgba(0, 0, 0, 0.94);

    align-items: center;
    justify-content: center;
}

#fullscreenImage {
    max-width: 95vw;
    max-height: 95vh;

    object-fit: contain;
}

#closeFullscreen {
    position: absolute;

    top: 14px;
    right: 20px;

    color: #ffffff;

    font-size: 32px;

    cursor: pointer;

    font-weight: 300;

    line-height: 1;
}

</style>

</head>


<body>


<!-- ========================================================
     HEADER
     ======================================================== -->

<div id="header">

    <div id="title">
        Combined vs Individual
    </div>

    <div id="fileName">
        -
    </div>

    <div id="navigation">

        <button
            id="previousButton"
            onclick="previousImage()"
        >
            ← Previous
        </button>

        <div id="counter">
            -
        </div>

        <button
            id="nextButton"
            onclick="nextImage()"
        >
            Next →
        </button>

    </div>

</div>


<!-- ========================================================
     FILTERS
     ======================================================== -->

<div id="filters">

    <div class="filter-group">

        <input
            type="radio"
            name="filter"
            id="filterAll"
            value="all"
            checked
            onchange="applyFilter()"
        >

        <label for="filterAll">
            All
        </label>

    </div>


    <div class="filter-group">

        <input
            type="radio"
            name="filter"
            id="filterFound"
            value="found"
            onchange="applyFilter()"
        >

        <label for="filterFound">
            Found differs
        </label>

    </div>


    <div class="filter-group">

        <input
            type="radio"
            name="filter"
            id="filterAny"
            value="any"
            onchange="applyFilter()"
        >

        <label for="filterAny">
            Any difference
        </label>

    </div>


    <div id="stats">
        -
    </div>

</div>


<!-- ========================================================
     MAIN
     ======================================================== -->

<div id="main">


    <!-- ====================================================
         IMAGE
         ==================================================== -->

    <div id="imagePanel">

        <div id="imageContainer">

            <img
                id="mainImage"
                alt=""
                onclick="openFullscreen()"
            >

        </div>


        <div id="imageInfo">

            <div>
                <strong>File:</strong>
                <span id="infoFile">
                    -
                </span>
            </div>

            <div id="classes">
                <strong>Classes:</strong>
                <span id="infoClasses">
                    -
                </span>
            </div>

        </div>

    </div>


    <!-- ====================================================
         RESULTS
         ==================================================== -->

    <div id="resultsPanel">

        <div id="results">
        </div>

        <div
            id="empty"
            style="display: none;"
        >
            No comparisons match the selected filter.
        </div>

    </div>

</div>


<!-- ========================================================
     FULLSCREEN
     ======================================================== -->

<div
    id="fullscreen"
    onclick="closeFullscreen()"
>

    <div
        id="closeFullscreen"
        onclick="closeFullscreen()"
    >
        ×
    </div>

    <img
        id="fullscreenImage"
        alt=""
    >

</div>


<script>


// ============================================================
// STATE
// ============================================================

let data = [];

let filteredIndices = [];

let currentIndex = 0;

let currentFilter = "all";


// ============================================================
// INIT
// ============================================================

async function init() {

    const response = await fetch(
        "/api/data"
    );

    if (!response.ok) {
        throw new Error(
            "Failed to load data."
        );
    }

    const payload =
        await response.json();

    data =
        payload.results || [];

    applyFilter();
}


// ============================================================
// FILTER
// ============================================================

function applyFilter() {

    currentFilter =
        document.querySelector(
            'input[name="filter"]:checked'
        ).value;

    filteredIndices = [];

    for (
        let i = 0;
        i < data.length;
        i++
    ) {

        const item = data[i];

        if (
            currentFilter === "all"
        ) {

            filteredIndices.push(i);

            continue;
        }

        if (
            currentFilter === "found"
            &&
            item.num_found_differences > 0
        ) {

            filteredIndices.push(i);

            continue;
        }

        if (
            currentFilter === "any"
            &&
            item.num_differences > 0
        ) {

            filteredIndices.push(i);

            continue;
        }
    }

    if (
        filteredIndices.length === 0
    ) {

        currentIndex = 0;

        renderEmpty();

        return;
    }

    if (
        currentIndex >=
        filteredIndices.length
    ) {

        currentIndex =
            filteredIndices.length - 1;
    }

    renderCurrent();
}


// ============================================================
// CURRENT ITEM
// ============================================================

function getCurrentItem() {

    if (
        filteredIndices.length === 0
    ) {

        return null;
    }

    const realIndex =
        filteredIndices[currentIndex];

    return data[realIndex];
}


// ============================================================
// NAVIGATION
// ============================================================

function previousImage() {

    if (
        filteredIndices.length === 0
    ) {

        return;
    }

    if (
        currentIndex > 0
    ) {

        currentIndex--;

        renderCurrent();
    }
}


function nextImage() {

    if (
        filteredIndices.length === 0
    ) {

        return;
    }

    if (
        currentIndex <
        filteredIndices.length - 1
    ) {

        currentIndex++;

        renderCurrent();
    }
}


// ============================================================
// RENDER CURRENT
// ============================================================

function renderCurrent() {

    const item =
        getCurrentItem();

    if (!item) {

        renderEmpty();

        return;
    }

    document.getElementById(
        "empty"
    ).style.display = "none";

    document.getElementById(
        "results"
    ).style.display = "block";


    // --------------------------------------------------------
    // Header
    // --------------------------------------------------------

    document.getElementById(
        "fileName"
    ).textContent =
        item.file || "-";

    document.getElementById(
        "counter"
    ).textContent =
        `${currentIndex + 1} / ${filteredIndices.length}`;


    // --------------------------------------------------------
    // Image
    // --------------------------------------------------------

    const imageUrl =
        "/api/image/" +
        encodeURIComponent(
            item.file
        );

    document.getElementById(
        "mainImage"
    ).src =
        imageUrl;

    document.getElementById(
        "fullscreenImage"
    ).src =
        imageUrl;


    // --------------------------------------------------------
    // Info
    // --------------------------------------------------------

    document.getElementById(
        "infoFile"
    ).textContent =
        item.file || "-";

    document.getElementById(
        "infoClasses"
    ).textContent =
        (
            item.annotated_classes || []
        ).join(
            ", "
        ) || "-";


    // --------------------------------------------------------
    // Stats
    // --------------------------------------------------------

    document.getElementById(
        "stats"
    ).textContent =
        `${item.num_comparisons} combined queries · ` +
        `${item.num_differences} differences · ` +
        `${item.num_found_differences} found conflicts`;


    // --------------------------------------------------------
    // Query cards
    // --------------------------------------------------------

    renderComparisons(
        item.comparisons
    );


    // --------------------------------------------------------
    // Buttons
    // --------------------------------------------------------

    document.getElementById(
        "previousButton"
    ).disabled =
        currentIndex === 0;

    document.getElementById(
        "nextButton"
    ).disabled =
        currentIndex ===
        filteredIndices.length - 1;
}


// ============================================================
// RENDER EMPTY
// ============================================================

function renderEmpty() {

    document.getElementById(
        "results"
    ).style.display = "none";

    document.getElementById(
        "empty"
    ).style.display = "flex";

    document.getElementById(
        "fileName"
    ).textContent = "-";

    document.getElementById(
        "counter"
    ).textContent = "0 / 0";

    document.getElementById(
        "stats"
    ).textContent = "-";

    document.getElementById(
        "mainImage"
    ).removeAttribute(
        "src"
    );
}


// ============================================================
// RENDER COMPARISONS
// ============================================================

function renderComparisons(
    comparisons
) {

    const container =
        document.getElementById(
            "results"
        );

    container.innerHTML = "";

    const entries =
        Object.entries(
            comparisons || {}
        );


    for (
        const [
            query,
            comparison
        ]
        of entries
    ) {

        const difference =
            comparison.difference || {};

        const combined =
            comparison.combined || {};

        const individualResults =
            comparison.individual_results || {};

        /*
         * The JSON key remains "individual_union"
         * for compatibility with the result generator.
         *
         * Its contents now represent the INTERSECTION
         * of the individual query results.
         */
        const individualIntersection =
            comparison.individual_union || {};


        // ----------------------------------------------------
        // Filter individual query cards
        // ----------------------------------------------------

        if (
            currentFilter === "found"
            &&
            !difference.found_difference
        ) {

            continue;
        }

        if (
            currentFilter === "any"
            &&
            !hasAnyDifferenceJS(
                comparison
            )
        ) {

            continue;
        }


        // ----------------------------------------------------
        // Card
        // ----------------------------------------------------

        const card =
            document.createElement(
                "div"
            );

        const foundDifference =
            !!difference.found_difference;

        const anyDifference =
            hasAnyDifferenceJS(
                comparison
            );

        card.className =
            "queryCard";

        if (foundDifference) {

            card.classList.add(
                "foundDifference"
            );

        } else if (anyDifference) {

            card.classList.add(
                "anyDifference"
            );
        }


        // ----------------------------------------------------
        // Header
        // ----------------------------------------------------

        const header =
            document.createElement(
                "div"
            );

        header.className =
            "queryHeader";


        const queryName =
            document.createElement(
                "div"
            );

        queryName.className =
            "queryName";

        queryName.textContent =
            query;


        const classes =
            document.createElement(
                "div"
            );

        classes.className =
            "queryClasses";

        classes.textContent =
            (
                comparison.classes || []
            ).join(
                " + "
            );


        const badge =
            document.createElement(
                "div"
            );

        badge.className =
            "differenceBadge";

        if (foundDifference) {

            badge.textContent =
                "FOUND DIFF";

        } else if (anyDifference) {

            badge.textContent =
                "DIFFERENCE";

        } else {

            badge.textContent =
                "SAME";
        }


        header.appendChild(
            queryName
        );

        header.appendChild(
            classes
        );

        header.appendChild(
            badge
        );


        // ----------------------------------------------------
        // Grid
        // ----------------------------------------------------

        const grid =
            document.createElement(
                "div"
            );

        grid.className =
            "comparisonGrid";


        // ----------------------------------------------------
        // Combined
        // ----------------------------------------------------

        grid.appendChild(
            createMetricsColumn(
                "Combined",
                combined
            )
        );


        // ----------------------------------------------------
        // Individual intersection + class details
        // ----------------------------------------------------

        grid.appendChild(
            createIndividualColumn(
                individualResults,
                individualIntersection
            )
        );


        // ----------------------------------------------------
        // Difference
        // ----------------------------------------------------

        grid.appendChild(
            createDifferenceColumn(
                difference,
                combined,
                individualIntersection
            )
        );


        card.appendChild(
            header
        );

        card.appendChild(
            grid
        );

        container.appendChild(
            card
        );
    }


    if (
        container.children.length === 0
    ) {

        container.innerHTML =
            '<div style="' +
            'padding:30px;' +
            'text-align:center;' +
            'color:#777;' +
            '">' +
            'No comparisons match the selected filter.' +
            '</div>';
    }
}


// ============================================================
// COMBINED METRICS COLUMN
// ============================================================

function createMetricsColumn(
    title,
    values
) {

    const column =
        document.createElement(
            "div"
        );

    column.className =
        "comparisonColumn";


    const titleElement =
        document.createElement(
            "div"
        );

    titleElement.className =
        "columnTitle";

    titleElement.textContent =
        title;

    column.appendChild(
        titleElement
    );


    appendBooleanMetric(
        column,
        "Original",
        values.original
    );

    appendBooleanMetric(
        column,
        "Squared",
        values.squared
    );

    appendBooleanMetric(
        column,
        "Segmented original",
        values.segmented_original
    );

    appendBooleanMetric(
        column,
        "Segmented squared",
        values.segmented_squared
    );


    appendMetric(
        column,
        "Max cosine",
        formatNumber(
            values.max_cosine
        )
    );

    appendMetric(
        column,
        "Max modified",
        formatNumber(
            values.max_modified_similarity
        )
    );


    appendFoundBetterBoxes(
        column,
        values
    );


    return column;
}


// ============================================================
// INDIVIDUAL COLUMN
// ============================================================

function createIndividualColumn(
    individualResults,
    individualIntersection
) {

    const column =
        document.createElement(
            "div"
        );

    column.className =
        "comparisonColumn";


    // --------------------------------------------------------
    // TOP: Individual intersection
    // --------------------------------------------------------

    const title =
        document.createElement(
            "div"
        );

    title.className =
        "columnTitle";

    title.textContent =
        "Individual intersection";

    column.appendChild(
        title
    );


    appendBooleanMetric(
        column,
        "Original",
        individualIntersection.original
    );

    appendBooleanMetric(
        column,
        "Squared",
        individualIntersection.squared
    );

    appendBooleanMetric(
        column,
        "Segmented original",
        individualIntersection.segmented_original
    );

    appendBooleanMetric(
        column,
        "Segmented squared",
        individualIntersection.segmented_squared
    );

    appendMetric(
        column,
        "Max cosine",
        formatNumber(
            individualIntersection.max_cosine
        )
    );

    appendMetric(
        column,
        "Max modified",
        formatNumber(
            individualIntersection.max_modified_similarity
        )
    );

    appendFoundBetterBoxes(
        column,
        individualIntersection
    );


    // --------------------------------------------------------
    // BOTTOM: Individual class details
    // --------------------------------------------------------

    const details =
        document.createElement(
            "div"
        );

    details.className =
        "individualDetails";


    const detailsTitle =
        document.createElement(
            "div"
        );

    detailsTitle.className =
        "individualDetailsTitle";

    detailsTitle.textContent =
        "Individual classes";

    details.appendChild(
        detailsTitle
    );


    const resultsContainer =
        document.createElement(
            "div"
        );

    resultsContainer.className =
        "individualResults";


    const entries =
        Object.entries(
            individualResults || {}
        );


    // --------------------------------------------------------
    // Individual class results
    // --------------------------------------------------------

    for (
        const [
            className,
            values
        ]
        of entries
    ) {

        const result =
            document.createElement(
                "div"
            );

        result.className =
            "individualResult";


        const resultTitle =
            document.createElement(
                "div"
            );

        resultTitle.className =
            "individualResultTitle";

        resultTitle.textContent =
            className;


        const resultBody =
            document.createElement(
                "div"
            );

        resultBody.className =
            "individualResultBody";


        appendBooleanMetric(
            resultBody,
            "Original",
            values.original
        );

        appendBooleanMetric(
            resultBody,
            "Squared",
            values.squared
        );

        appendBooleanMetric(
            resultBody,
            "Segmented original",
            values.segmented_original
        );

        appendBooleanMetric(
            resultBody,
            "Segmented squared",
            values.segmented_squared
        );

        appendMetric(
            resultBody,
            "Max cosine",
            formatNumber(
                values.max_cosine
            )
        );

        appendMetric(
            resultBody,
            "Max modified",
            formatNumber(
                values.max_modified_similarity
            )
        );

        appendFoundBetterBoxes(
            resultBody,
            values
        );


        result.appendChild(
            resultTitle
        );

        result.appendChild(
            resultBody
        );

        resultsContainer.appendChild(
            result
        );
    }


    details.appendChild(
        resultsContainer
    );

    column.appendChild(
        details
    );


    return column;
}


// ============================================================
// DIFFERENCE COLUMN
// ============================================================

function createDifferenceColumn(
    difference,
    combined,
    individual
) {

    const column =
        document.createElement(
            "div"
        );

    column.className =
        "comparisonColumn";


    const title =
        document.createElement(
            "div"
        );

    title.className =
        "columnTitle";

    title.textContent =
        "Combined − Individual intersection";

    column.appendChild(
        title
    );


    appendDifferenceMetric(
        column,
        "Max cosine",
        difference.max_cosine_difference
    );

    appendDifferenceMetric(
        column,
        "Max modified",
        difference.max_modified_similarity_difference
    );


    appendBooleanDifference(
        column,
        "Original",
        difference.original_difference
    );

    appendBooleanDifference(
        column,
        "Squared",
        difference.squared_difference
    );

    appendBooleanDifference(
        column,
        "Segmented original",
        difference.segmented_original_difference
    );

    appendBooleanDifference(
        column,
        "Segmented squared",
        difference.segmented_squared_difference
    );

    appendBooleanDifference(
        column,
        "Found",
        difference.found_difference
    );

    appendBooleanDifference(
        column,
        "Better",
        difference.better_difference
    );


    // --------------------------------------------------------
    // Found comparison
    // --------------------------------------------------------

    const foundBox =
        document.createElement(
            "div"
        );

    if (
        combined.found !==
        individual.found
    ) {

        foundBox.className =
            "foundBox foundConflict";

        foundBox.textContent =
            combined.found
                ? "COMBINED ONLY"
                : "INDIVIDUAL INTERSECTION ONLY";

    } else {

        foundBox.className =
            "foundBox " +
            (
                combined.found
                    ? "foundYes"
                    : "foundNo"
            );

        foundBox.textContent =
            combined.found
                ? "BOTH FOUND"
                : "BOTH NOT FOUND";
    }

    column.appendChild(
        foundBox
    );


    return column;
}


// ============================================================
// FOUND / BETTER BOXES
// ============================================================

function appendFoundBetterBoxes(
    column,
    values
) {

    const foundBox =
        document.createElement(
            "div"
        );

    foundBox.className =
        "foundBox " +
        (
            values.found
                ? "foundYes"
                : "foundNo"
        );

    foundBox.textContent =
        values.found
            ? "FOUND"
            : "NOT FOUND";

    column.appendChild(
        foundBox
    );


    const betterBox =
        document.createElement(
            "div"
        );

    betterBox.className =
        "foundBox " +
        (
            values.better
                ? "foundYes"
                : "foundNo"
        );

    betterBox.style.marginTop =
        "5px";

    betterBox.textContent =
        values.better
            ? "BETTER"
            : "NOT BETTER";

    column.appendChild(
        betterBox
    );
}


// ============================================================
// METRIC HELPERS
// ============================================================

function appendMetric(
    column,
    name,
    value
) {

    const row =
        document.createElement(
            "div"
        );

    row.className =
        "metric";


    const nameElement =
        document.createElement(
            "span"
        );

    nameElement.className =
        "metricName";

    nameElement.textContent =
        name;


    const valueElement =
        document.createElement(
            "span"
        );

    valueElement.className =
        "metricValue";

    valueElement.textContent =
        value;


    row.appendChild(
        nameElement
    );

    row.appendChild(
        valueElement
    );

    column.appendChild(
        row
    );
}


function appendBooleanMetric(
    column,
    name,
    value
) {

    const row =
        document.createElement(
            "div"
        );

    row.className =
        "metric";


    const nameElement =
        document.createElement(
            "span"
        );

    nameElement.className =
        "metricName";

    nameElement.textContent =
        name;


    const valueElement =
        document.createElement(
            "span"
        );

    valueElement.className =
        "metricValue " +
        (
            value
                ? "booleanTrue"
                : "booleanFalse"
        );

    valueElement.textContent =
        value
            ? "TRUE"
            : "FALSE";


    row.appendChild(
        nameElement
    );

    row.appendChild(
        valueElement
    );

    column.appendChild(
        row
    );
}


function appendDifferenceMetric(
    column,
    name,
    value
) {

    let text =
        formatNumber(
            value
        );

    let className =
        "metricDiffZero";

    if (
        value > 0
    ) {

        className =
            "metricDiffPositive";

        text =
            "+" + text;

    } else if (
        value < 0
    ) {

        className =
            "metricDiffNegative";
    }


    const row =
        document.createElement(
            "div"
        );

    row.className =
        "metric";


    const nameElement =
        document.createElement(
            "span"
        );

    nameElement.className =
        "metricName";

    nameElement.textContent =
        name;


    const valueElement =
        document.createElement(
            "span"
        );

    valueElement.className =
        "metricValue " +
        className;

    valueElement.textContent =
        text;


    row.appendChild(
        nameElement
    );

    row.appendChild(
        valueElement
    );

    column.appendChild(
        row
    );
}


function appendBooleanDifference(
    column,
    name,
    difference
) {

    const row =
        document.createElement(
            "div"
        );

    row.className =
        "metric";


    const nameElement =
        document.createElement(
            "span"
        );

    nameElement.className =
        "metricName";

    nameElement.textContent =
        name;


    const valueElement =
        document.createElement(
            "span"
        );

    valueElement.className =
        "metricValue " +
        (
            difference
                ? "metricDiffPositive"
                : "metricDiffZero"
        );

    valueElement.textContent =
        difference
            ? "DIFFERENT"
            : "SAME";


    row.appendChild(
        nameElement
    );

    row.appendChild(
        valueElement
    );

    column.appendChild(
        row
    );
}


// ============================================================
// HELPERS
// ============================================================

function formatNumber(
    value
) {

    if (
        value === null ||
        value === undefined ||
        Number.isNaN(value)
    ) {

        return "-";
    }

    return Number(
        value
    ).toFixed(6);
}


function hasAnyDifferenceJS(
    comparison
) {

    const d =
        comparison.difference || {};

    return (
        d.max_cosine_difference !== 0
        ||
        d.max_modified_similarity_difference !== 0
        ||
        !!d.original_difference
        ||
        !!d.squared_difference
        ||
        !!d.segmented_original_difference
        ||
        !!d.segmented_squared_difference
        ||
        !!d.found_difference
        ||
        !!d.better_difference
    );
}


// ============================================================
// FULLSCREEN
// ============================================================

function openFullscreen() {

    const image =
        document.getElementById(
            "mainImage"
        );

    if (
        !image.src
    ) {

        return;
    }

    document.getElementById(
        "fullscreen"
    ).style.display =
        "flex";
}


function closeFullscreen() {

    document.getElementById(
        "fullscreen"
    ).style.display =
        "none";
}


// ============================================================
// KEYBOARD
// ============================================================

document.addEventListener(
    "keydown",
    function(event) {

        if (
            event.key === "ArrowLeft"
        ) {

            previousImage();

            event.preventDefault();

        } else if (
            event.key === "ArrowRight"
        ) {

            nextImage();

            event.preventDefault();

        } else if (
            event.key === "Escape"
        ) {

            closeFullscreen();
        }

    }
);


// ============================================================
// START
// ============================================================

init().catch(
    function(error) {

        console.error(
            error
        );

        document.getElementById(
            "empty"
        ).style.display =
            "flex";

        document.getElementById(
            "empty"
        ).textContent =
            "Failed to load results: " +
            error.message;
    }
);

</script>

</body>

</html>
"""


# ============================================================
# MAIN
# ============================================================

def main():

    global RESULTS
    global IMAGE_ITEMS
    global RESULTS_PATH
    global IMAGES_DIR

    parser = argparse.ArgumentParser(
        description=(
            "FastAPI viewer for comparing "
            "combined CLIP queries against "
            "the intersection of individual queries."
        )
    )

    parser.add_argument(
        "--results",
        type=Path,
        default=DEFAULT_RESULTS,
        help=(
            "Path to "
            "combined_vs_individual.json."
        ),
    )

    parser.add_argument(
        "--images-dir",
        type=Path,
        default=DEFAULT_IMAGES_DIR,
        help=(
            "Directory containing source images."
        ),
    )

    parser.add_argument(
        "--host",
        type=str,
        default=DEFAULT_HOST,
        help="Server host.",
    )

    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help="Server port.",
    )

    args = parser.parse_args()

    RESULTS_PATH = (
        args.results.resolve()
    )

    IMAGES_DIR = (
        args.images_dir.resolve()
    )

    # --------------------------------------------------------
    # Load
    # --------------------------------------------------------

    log(
        f"Loading results: "
        f"{RESULTS_PATH}"
    )

    RESULTS = load_results(
        RESULTS_PATH
    )

    IMAGE_ITEMS = build_image_items(
        RESULTS
    )

    log(
        f"Images in results: "
        f"{len(IMAGE_ITEMS)}"
    )

    log(
        f"Images directory: "
        f"{IMAGES_DIR}"
    )

    # --------------------------------------------------------
    # Start server
    # --------------------------------------------------------

    log(
        "Starting viewer:"
    )

    log(
        f"  http://{args.host}:{args.port}"
    )

    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
    )


if __name__ == "__main__":
    main()
