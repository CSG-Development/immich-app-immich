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

RESULTS_PATH = (
    BASE_DIR
    / "voc_similarity"
    / "results.json"
)

IMAGES_DIR = (
    BASE_DIR
    / "voc_subset"
    / "images"
)


app = FastAPI()


# ============================================================
# API
# ============================================================

@app.get("/api/results")
async def results():
    with open(
        RESULTS_PATH,
        "r",
        encoding="utf-8",
    ) as f:
        return JSONResponse(
            json.load(f)
        )


@app.get("/image/{filename:path}")
async def image(filename: str):
    path = IMAGES_DIR / filename

    if not path.is_file():
        return JSONResponse(
            {
                "error": "Image not found"
            },
            status_code=404,
        )

    return FileResponse(path)


# ============================================================
# HTML
# ============================================================

HTML = r"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>VOC CLIP Similarity Viewer</title>

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
    font-family: Arial, sans-serif;
    overflow: hidden;
}


/* ============================================================
   TOOLBAR
   ============================================================ */

#toolbar {
    height: 60px;

    display: flex;
    align-items: center;

    gap: 10px;

    padding: 10px 20px;

    border-bottom: 1px solid #ccc;
}

#toolbar label {
    font-weight: bold;
}

#group-select {
    min-width: 130px;

    padding: 5px 8px;

    font-size: 14px;
}

/* MODIFIED: Increased width to accommodate longer text like 'parson and chair (43/45)' */
#query-select {
    min-width: 400px;

    padding: 5px 8px;

    font-size: 14px;
}

#columns {
    width: 60px;

    padding: 5px;

    font-size: 14px;
}

#hide-perfect {
    width: 16px;
    height: 16px;

    margin-left: 10px;
}

button {
    padding: 6px 12px;

    font-size: 14px;

    cursor: pointer;
}


/* ============================================================
   CONTENT
   ============================================================ */

#content {
    height: calc(100vh - 60px);

    display: grid;

    grid-template-columns: 1fr 1fr;

    overflow: hidden;
}


/* ============================================================
   PANELS
   ============================================================ */

.panel {
    min-width: 0;

    height: 100%;

    overflow-y: auto;
    overflow-x: hidden;

    padding: 0 20px 20px 20px;
}

.panel + .panel {
    border-left: 1px solid #ccc;
}


.panel-header {
    position: sticky;

    top: 0;

    z-index: 10;

    background: white;

    padding: 12px 0;

    margin-bottom: 10px;

    border-bottom: 1px solid #ccc;

    font-size: 20px;

    font-weight: 800;
}


/* ============================================================
   GRID
   ============================================================ */

.grid {
    display: grid;

    gap: 20px;

    align-items: start;
}


/* ============================================================
   IMAGE ITEM
   ============================================================ */

.item {
    min-width: 0;

    cursor: pointer;

    position: relative;
}


.image-wrapper {
    position: relative;

    width: 100%;

    aspect-ratio: 1;

    background: #eee;

    overflow: hidden;
}


.image-wrapper img {
    width: 100%;
    height: 100%;

    object-fit: contain;

    display: block;
}


/*
 * Image found by modified embeddings but not by
 * the original embedding.
 */

.item.modified-only .image-wrapper {
    outline: 4px solid #00a000;

    outline-offset: -4px;
}


.similarity {
    margin-top: 5px;

    text-align: center;

    font-size: 13px;

    font-weight: bold;

    color: #444;
}


/* ============================================================
   TOOLTIP
   ============================================================ */

.tooltip {
    position: fixed;

    display: none;

    z-index: 2000;

    padding: 8px 10px;

    background: rgba(0, 0, 0, 0.9);

    color: white;

    border-radius: 4px;

    font-size: 13px;

    line-height: 1.5;

    white-space: nowrap;

    pointer-events: none;
}


/* ============================================================
   FULLSCREEN
   ============================================================ */

#fullscreen {
    display: none;

    position: fixed;

    inset: 0;

    z-index: 1000;

    background: rgba(0, 0, 0, 0.9);

    align-items: center;

    justify-content: center;

    cursor: pointer;
}


#fullscreen img {
    max-width: 99vw;
    max-height: 99vh;

    object-fit: contain;

    cursor: default;
}


#fullscreen-close {
    position: absolute;

    top: 20px;
    right: 25px;

    z-index: 1001;

    border: none;

    background: none;

    color: white;

    font-size: 42px;

    font-weight: 300;

    line-height: 1;

    cursor: pointer;

    padding: 0;
}

</style>
</head>


<body>


<!-- ==========================================================
     TOOLBAR
     ========================================================== -->

<div id="toolbar">

    <label for="group-select">
        Group:
    </label>

    <select id="group-select">
    </select>


    <label for="query-select">
        Query:
    </label>

    <select id="query-select">
    </select>


    <label for="columns">
        Columns:
    </label>

    <input
        id="columns"
        type="number"
        min="1"
        max="20"
        value="4"
    >


    <label for="hide-perfect">

        <input
            id="hide-perfect"
            type="checkbox"
        >

        Hide similarity 1.0000

    </label>


    <button id="apply">
        Apply
    </button>

</div>


<!-- ==========================================================
     CONTENT
     ========================================================== -->

<div id="content">


    <div
        id="original-panel"
        class="panel"
    >

        <div
            class="panel-header"
            id="original-header"
        >
            original
        </div>

        <div
            id="original-grid"
            class="grid"
        ></div>

    </div>


    <div
        id="modified-panel"
        class="panel"
    >

        <div
            class="panel-header"
            id="modified-header"
        >
            modified
        </div>

        <div
            id="modified-grid"
            class="grid"
        ></div>

    </div>


</div>


<!-- ==========================================================
     TOOLTIP
     ========================================================== -->

<div
    id="tooltip"
    class="tooltip"
></div>


<!-- ==========================================================
     FULLSCREEN
     ========================================================== -->

<div id="fullscreen">

    <button id="fullscreen-close">
        &times;
    </button>

    <img id="fullscreen-image">

</div>


<script>


// ============================================================
// STATE
// ============================================================

let results = null;

let currentGroup = null;

let currentQuery = null;


// ============================================================
// DOM
// ============================================================

const groupSelect =
    document.getElementById(
        "group-select"
    );

const querySelect =
    document.getElementById(
        "query-select"
    );

const columnsInput =
    document.getElementById(
        "columns"
    );

const hidePerfectInput =
    document.getElementById(
        "hide-perfect"
    );

const applyButton =
    document.getElementById(
        "apply"
    );


const originalPanel =
    document.getElementById(
        "original-panel"
    );

const modifiedPanel =
    document.getElementById(
        "modified-panel"
    );


const originalGrid =
    document.getElementById(
        "original-grid"
    );

const modifiedGrid =
    document.getElementById(
        "modified-grid"
    );


const originalHeader =
    document.getElementById(
        "original-header"
    );

const modifiedHeader =
    document.getElementById(
        "modified-header"
    );


const tooltip =
    document.getElementById(
        "tooltip"
    );


const fullscreen =
    document.getElementById(
        "fullscreen"
    );

const fullscreenImage =
    document.getElementById(
        "fullscreen-image"
    );

const fullscreenClose =
    document.getElementById(
        "fullscreen-close"
    );


// ============================================================
// LOAD RESULTS
// ============================================================

async function loadResults() {

    const response =
        await fetch(
            "/api/results"
        );

    if (!response.ok) {
        throw new Error(
            "Failed to load results"
        );
    }

    results =
        await response.json();


    /*
     * The JSON format is:
     *
     * {
     *   "config": {...},
     *   "queries": {...},
     *   "results": [
     *       {
     *           "file": "...",
     *           "groups": {
     *               "individual": {
     *                   "aeroplane": {...}
     *               },
     *               ...
     *           }
     *       },
     *       ...
     *   ],
     *   "statistics": {...}
     * }
     *
     * Build an index suitable for the viewer:
     *
     *   groups
     *     -> group
     *         -> query
     *             -> image results
     */

    buildViewerIndex();

    initializeSelectors();
}


// ============================================================
// BUILD VIEWER INDEX
// ============================================================

function buildViewerIndex() {

    const imageResults =
        results.results || [];


    const groups = {};


    for (
        const imageResult
        of imageResults
    ) {

        const file =
            imageResult.file;


        if (!file) {
            continue;
        }


        const imageGroups =
            imageResult.groups || {};


        for (
            const groupName
            of Object.keys(
                imageGroups
            )
        ) {

            if (
                !groups[groupName]
            ) {

                groups[groupName] = {};
            }


            const groupResults =
                imageGroups[groupName] || {};


            for (
                const query
                of Object.keys(
                    groupResults
                )
            ) {

                if (
                    !groups[groupName][query]
                ) {

                    groups[groupName][query] =
                        [];
                }


                const values =
                    groupResults[query];


                groups[groupName][query].push(
                    {
                        file: file,

                        original_modified_similarity:
                            Number(
                                values.original_modified_similarity
                            ),

                        max_modified_similarity:
                            Number(
                                values.max_modified_similarity
                            ),

                        best_embedding_by_modified_similarity:
                            values.best_embedding_by_modified_similarity,

                        original:
                            Boolean(
                                values.original
                            ),

                        squared:
                            Boolean(
                                values.squared
                            ),

                        segmented_original:
                            Boolean(
                                values.segmented_original
                            ),

                        segmented_squared:
                            Boolean(
                                values.segmented_squared
                            ),

                        found:
                            Boolean(
                                values.found
                            ),

                        better:
                            Boolean(
                                values.better
                            ),
                    }
                );
            }
        }
    }


    results.viewer =
        {
            groups: groups
        };
}


// ============================================================
// INITIALIZE SELECTORS
// ============================================================

function initializeSelectors() {

    const groups =
        results.viewer?.groups || {};


    groupSelect.innerHTML =
        "";


    const groupNames =
        Object.keys(groups);


    if (
        groupNames.length === 0
    ) {

        currentGroup = null;

        currentQuery = null;

        return;
    }


    /*
     * Prefer the standard order:
     *
     * individual
     * combined
     * counted
     *
     * while still supporting any other
     * group names.
     */

    const preferredOrder = [
        "individual",
        "combined",
        "counted",
    ];


    const orderedGroupNames = [
        ...preferredOrder.filter(
            name =>
                groupNames.includes(
                    name
                )
        ),

        ...groupNames.filter(
            name =>
                !preferredOrder.includes(
                    name
                )
        ),
    ];


    for (
        const groupName
        of orderedGroupNames
    ) {

        const option =
            document.createElement(
                "option"
            );

        option.value =
            groupName;

        option.textContent =
            groupName;

        groupSelect.appendChild(
            option
        );
    }


    currentGroup =
        orderedGroupNames[0];

    groupSelect.value =
        currentGroup;


    updateQueries();
}


// ============================================================
// UPDATE QUERY SELECTOR
// ============================================================

function updateQueries() {

    const group = results.viewer.groups[currentGroup];

    querySelect.innerHTML = "";

    if (!group) {
        currentQuery = null;
        return;
    }

    // MODIFIED: Pre-pass to calculate counts for each query
    const queries = Object.keys(group).sort();
    const queryCounts = {};

    for (const query of queries) {
        let originalCount = 0;
        let modifiedCount = 0;
        
        const items = group[query] || [];

        for (const item of items) {
            if (item.original) {
                originalCount++;
            }
            if (item.found) {
                modifiedCount++;
            }
        }

        queryCounts[query] = {
            original: originalCount,
            modified: modifiedCount
        };
    }

    for (const query of queries) {
        const option = document.createElement("option");
        
        // MODIFIED: Store raw value separately and format the display text
        option.value = query;
        option.setAttribute('data-query-value', query);
        
        const counts = queryCounts[query];
        option.textContent = `${query} (${counts.original}/${counts.modified})`;

        querySelect.appendChild(option);
    }

    if (queries.length === 0) {
        currentQuery = null;
        return;
    }

    currentQuery = queries[0];
    
    // MODIFIED: Set value from data attribute to ensure correct matching
    const firstOption = querySelect.querySelector('option');
    if (firstOption) {
        querySelect.value = firstOption.getAttribute('data-query-value');
    }

    originalPanel.scrollTop = 0;
    modifiedPanel.scrollTop = 0;

    render();
}


// ============================================================
// GET QUERY RESULTS
// ============================================================

function getQueryItems() {

    if (
        !results
        ||
        !results.viewer
        ||
        !results.viewer.groups
        ||
        !currentGroup
        ||
        !currentQuery
    ) {

        return [];
    }


    const group =
        results.viewer.groups[
            currentGroup
        ];


    if (!group) {
        return [];
    }


    return (
        group[currentQuery] || []
    );
}


// ============================================================
// CREATE IMAGE ITEM
// ============================================================

function createItem(
    item,
    modifiedOnly,
    originalSimilarity
) {

    const element =
        document.createElement(
            "div"
        );

    element.className =
        "item";


    if (modifiedOnly) {

        element.classList.add(
            "modified-only"
        );
    }


    const wrapper =
        document.createElement(
            "div"
        );

    wrapper.className =
        "image-wrapper";


    const img =
        document.createElement(
            "img"
        );

    img.loading =
        "lazy";

    img.decoding =
        "async";

    img.src =
        "/image/" +
        item.file
            .split("/")
            .map(
                part =>
                    encodeURIComponent(
                        part
                    )
            )
            .join("/");

    img.alt =
        item.file;


    wrapper.appendChild(
        img
    );

    element.appendChild(
        wrapper
    );


    const similarity =
        document.createElement(
            "div"
        );

    similarity.className =
        "similarity";


    similarity.textContent =
        Number(
            item.modified_similarity
        ).toFixed(6);


    element.appendChild(
        similarity
    );


    // --------------------------------------------------------
    // Tooltip
    // --------------------------------------------------------

    element.addEventListener(
        "mouseenter",
        (event) => {

            let tooltipText =
                `${escapeHtml(item.file)}<br>` +
                `modified similarity: ` +
                `${Number(
                    item.modified_similarity
                ).toFixed(6)}`;


            if (
                originalSimilarity !== null
                &&
                originalSimilarity !== undefined
                &&
                Number.isFinite(
                    Number(
                        originalSimilarity
                    )
                )
            ) {

                tooltipText +=
                    `<br>original similarity: ` +
                    `${Number(
                        originalSimilarity
                    ).toFixed(6)}`;
            }


            if (
                item.best_embedding_by_modified_similarity !==
                undefined
                &&
                item.best_embedding_by_modified_similarity !==
                null
            ) {

                tooltipText +=
                    `<br>best embedding: ` +
                    `${item.best_embedding_by_modified_similarity}`;
            }


            tooltip.innerHTML =
                tooltipText;

            tooltip.style.display =
                "block";

            updateTooltipPosition(
                event
            );
        }
    );


    element.addEventListener(
        "mousemove",
        (event) => {

            updateTooltipPosition(
                event
            );
        }
    );


    element.addEventListener(
        "mouseleave",
        () => {

            tooltip.style.display =
                "none";
        }
    );


    // --------------------------------------------------------
    // Fullscreen
    // --------------------------------------------------------

    element.addEventListener(
        "click",
        () => {

            fullscreenImage.src =
                img.src;

            fullscreen.style.display =
                "flex";
        }
    );


    return element;
}


// ============================================================
// HTML ESCAPE
// ============================================================

function escapeHtml(
    value
) {

    return String(
        value
    )
        .replace(
            /&/g,
            "&amp;"
        )
        .replace(
            /</g,
            "&lt;"
        )
        .replace(
            />/g,
            "&gt;"
        )
        .replace(
            /"/g,
            "&quot;"
        )
        .replace(
            /'/g,
            "&#039;"
        );
}


// ============================================================
// TOOLTIP POSITION
// ============================================================

function updateTooltipPosition(
    event
) {

    const offset = 12;

    const tooltipRect =
        tooltip.getBoundingClientRect();


    let left =
        event.clientX +
        offset;

    let top =
        event.clientY +
        offset;


    if (
        left +
        tooltipRect.width >
        window.innerWidth
    ) {

        left =
            event.clientX -
            tooltipRect.width -
            offset;
    }


    if (
        top +
        tooltipRect.height >
        window.innerHeight
    ) {

        top =
            event.clientY -
            tooltipRect.height -
            offset;
    }


    tooltip.style.left =
        `${left}px`;

    tooltip.style.top =
        `${top}px`;
}


// ============================================================
// RENDER PANEL
// ============================================================

function renderPanel(
    panel,
    grid,
    items,
    originalSimilarityMap,
    isModifiedPanel
) {

    grid.innerHTML =
        "";


    const columns =
        Math.max(
            1,
            Math.min(
                20,
                parseInt(
                    columnsInput.value,
                    10
                ) || 1
            )
        );


    grid.style.gridTemplateColumns =
        `repeat(${columns}, minmax(0, 1fr))`;


    let filteredItems =
        items;


    if (
        hidePerfectInput.checked
    ) {

        filteredItems =
            items.filter(
                item =>
                    Number(
                        item.modified_similarity
                    ) !== 1
            );
    }


    const sortedItems =
        [
            ...filteredItems
        ].sort(
            (a, b) =>
                Number(
                    b.modified_similarity
                )
                -
                Number(
                    a.modified_similarity
                )
        );


    for (
        const item
        of sortedItems
    ) {

        /*
         * `better` is calculated by the generator as:
         *
         *     not original and found
         *
         * Therefore it identifies images which were
         * not found by the original embedding but were
         * found by one of the modified embeddings.
         */

        const modifiedOnly =
            isModifiedPanel &&
            item.better;


        const originalSimilarity =
            originalSimilarityMap.get(
                item.file
            );


        grid.appendChild(
            createItem(
                item,
                modifiedOnly,
                originalSimilarity
            )
        );
    }


    return sortedItems.length;
}


// ============================================================
// RENDER
// ============================================================

function render() {

    if (
        !currentGroup
        ||
        !currentQuery
        ||
        !results
    ) {

        originalGrid.innerHTML =
            "";

        modifiedGrid.innerHTML =
            "";

        originalHeader.textContent =
            "original (0)";

        modifiedHeader.textContent =
            "modified (0)";

        return;
    }


    const items =
        getQueryItems();


    /*
     * --------------------------------------------------------
     * ORIGINAL
     * --------------------------------------------------------
     *
     * `original` is true when the original embedding
     * (embedding 0) reaches the threshold.
     *
     * Therefore only these images belong to the
     * original panel.
     */

    const original =
        items.filter(
            item =>
                item.original
        );


    /*
     * --------------------------------------------------------
     * MODIFIED
     * --------------------------------------------------------
     *
     * `found` is true when ANY of the 20 embeddings
     * reaches the threshold.
     *
     * Therefore the modified panel contains:
     *
     *   original === true  && found === true
     *
     * and:
     *
     *   original === false && found === true
     *
     * The second category is exactly the set of
     * newly found images.
     */

    const modified =
        items.filter(
            item =>
                item.found
        );


    /*
     * Original similarity for every image is the
     * similarity of embedding 0.
     */

    const originalSimilarityMap =
        new Map(
            items.map(
                item => [
                    item.file,
                    Number(
                        item.original_modified_similarity
                    ),
                ]
            )
        );


    /*
     * For the original panel the displayed similarity
     * is the original embedding similarity.
     */

    const originalDisplayItems =
        original.map(
            item => ({
                ...item,

                modified_similarity:
                    item.original_modified_similarity,
            })
        );


    /*
     * For the modified panel the displayed similarity
     * is the maximum similarity over all embeddings.
     */

    const modifiedDisplayItems =
        modified.map(
            item => ({
                ...item,

                modified_similarity:
                    item.max_modified_similarity,
            })
        );


    const originalCount =
        renderPanel(
            originalPanel,
            originalGrid,
            originalDisplayItems,
            originalSimilarityMap,
            false
        );


    const modifiedCount =
        renderPanel(
            modifiedPanel,
            modifiedGrid,
            modifiedDisplayItems,
            originalSimilarityMap,
            true
        );


    originalHeader.textContent =
        `original (${originalCount})`;


    modifiedHeader.textContent =
        `modified (${modifiedCount})`;
}


// ============================================================
// GROUP CHANGE
// ============================================================

groupSelect.addEventListener(
    "change",
    () => {

        currentGroup =
            groupSelect.value;


        originalPanel.scrollTop =
            0;

        modifiedPanel.scrollTop =
            0;


        updateQueries();
    }
);


// ============================================================
// QUERY CHANGE
// ============================================================

querySelect.addEventListener(
    "change",
    () => {
        // MODIFIED: Read actual query value from data attribute
        const selectedOption = querySelect.selectedOptions[0];
        currentQuery = selectedOption ? selectedOption.getAttribute('data-query-value') : null;

        originalPanel.scrollTop = 0;
        modifiedPanel.scrollTop = 0;

        render();
    }
);


// ============================================================
// APPLY
// ============================================================

applyButton.addEventListener(
    "click",
    () => {

        render();
    }
);


// ============================================================
// WINDOW RESIZE
// ============================================================

window.addEventListener(
    "resize",
    () => {

        render();
    }
);


// ============================================================
// FULLSCREEN CLOSE
// ============================================================

fullscreenClose.addEventListener(
    "click",
    (event) => {

        event.stopPropagation();

        fullscreen.style.display =
            "none";

        fullscreenImage.src =
            "";
    }
);


fullscreen.addEventListener(
    "click",
    (event) => {

        if (
            event.target ===
            fullscreen
        ) {

            fullscreen.style.display =
                "none";

            fullscreenImage.src =
                "";
        }
    }
);


// ============================================================
// ESCAPE
// ============================================================

document.addEventListener(
    "keydown",
    (event) => {

        if (
            event.key ===
            "Escape"
        ) {

            fullscreen.style.display =
                "none";

            fullscreenImage.src =
                "";
        }
    }
);


// ============================================================
// SYNCHRONIZED SCROLL
// ============================================================

let syncingScroll = false;


originalPanel.addEventListener(
    "scroll",
    () => {

        if (syncingScroll) {
            return;
        }


        syncingScroll = true;


        modifiedPanel.scrollTop =
            originalPanel.scrollTop;


        requestAnimationFrame(
            () => {

                syncingScroll = false;
            }
        );
    }
);


modifiedPanel.addEventListener(
    "scroll",
    () => {

        if (syncingScroll) {
            return;
        }


        syncingScroll = true;


        originalPanel.scrollTop =
            modifiedPanel.scrollTop;


        requestAnimationFrame(
            () => {

                syncingScroll = false;
            }
        );
    }
);


// ============================================================
// LOAD
// ============================================================

loadResults().catch(
    error => {

        console.error(
            error
        );
    }
);

</script>

</body>
</html>
"""


# ============================================================
# INDEX
# ============================================================

@app.get("/")
async def index():
    return HTMLResponse(
        HTML
    )


# ============================================================
# MAIN
# ============================================================

def main():

    global RESULTS_PATH, IMAGES_DIR

    parser = argparse.ArgumentParser(
        description="VOC CLIP similarity viewer"
    )

    parser.add_argument(
        "--results",
        type=Path,
        default=RESULTS_PATH,
        help="Path to results.json.",
    )

    parser.add_argument(
        "--images",
        type=Path,
        default=IMAGES_DIR,
        help="Directory containing images.",
    )

    parser.add_argument(
        "--host",
        default="127.0.0.1",
    )

    parser.add_argument(
        "--port",
        type=int,
        default=8000,
    )

    args = parser.parse_args()

    RESULTS_PATH = args.results
    IMAGES_DIR = args.images

    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
    )


# ============================================================
# ENTRY POINT
# ============================================================

if __name__ == "__main__":
    main()
