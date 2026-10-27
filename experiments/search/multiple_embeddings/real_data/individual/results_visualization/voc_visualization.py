import argparse
import json
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
import uvicorn


BASE_DIR = Path(__file__).resolve().parent
IMAGE_LISTS_PATH = (
    BASE_DIR
    / "voc_similarity_reprocessed"
    / "image_lists_similarity.json"
)
IMAGES_DIR = BASE_DIR / "voc_subset" / "images"


app = FastAPI()


@app.get("/api/image-lists")
async def image_lists():
    with open(IMAGE_LISTS_PATH, "r", encoding="utf-8") as f:
        return JSONResponse(json.load(f))


@app.get("/image/{filename:path}")
async def image(filename: str):
    path = IMAGES_DIR / filename

    if not path.is_file():
        return JSONResponse(
            {"error": "Image not found"},
            status_code=404,
        )

    return FileResponse(path)


HTML = r"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>VOC Image Comparison</title>

<style>
    * {
        box-sizing: border-box;
    }

    html, body {
        margin: 0;
        padding: 0;
        width: 100%;
        height: 100%;
        font-family: Arial, sans-serif;
        overflow: hidden;
    }

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

    #class-select {
        min-width: 180px;
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

    #content {
        height: calc(100vh - 60px);
        display: grid;
        grid-template-columns: 1fr 1fr;
        overflow: hidden;
    }

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

    .grid {
        display: grid;
        gap: 20px;
        align-items: start;
    }

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

<div id="toolbar">
    <label for="class-select">Class:</label>
    <select id="class-select"></select>

    <label for="columns">Columns:</label>
    <input id="columns" type="number" min="1" max="20" value="4">

    <label for="hide-perfect">
        <input id="hide-perfect" type="checkbox">
        Hide similarity 1.0000
    </label>

    <button id="apply">Apply</button>
</div>

<div id="content">
    <div id="original-panel" class="panel">
        <div class="panel-header" id="original-header">
            original
        </div>
        <div id="original-grid" class="grid"></div>
    </div>

    <div id="modified-panel" class="panel">
        <div class="panel-header" id="modified-header">
            modified
        </div>
        <div id="modified-grid" class="grid"></div>
    </div>
</div>

<div id="tooltip" class="tooltip"></div>

<div id="fullscreen">
    <button id="fullscreen-close">&times;</button>
    <img id="fullscreen-image">
</div>

<script>
let imageLists = {};
let currentClass = null;

const classSelect = document.getElementById("class-select");
const columnsInput = document.getElementById("columns");
const hidePerfectInput = document.getElementById("hide-perfect");
const applyButton = document.getElementById("apply");

const originalPanel = document.getElementById("original-panel");
const modifiedPanel = document.getElementById("modified-panel");

const originalGrid = document.getElementById("original-grid");
const modifiedGrid = document.getElementById("modified-grid");

const originalHeader = document.getElementById("original-header");
const modifiedHeader = document.getElementById("modified-header");

const tooltip = document.getElementById("tooltip");

const fullscreen = document.getElementById("fullscreen");
const fullscreenImage = document.getElementById("fullscreen-image");
const fullscreenClose = document.getElementById("fullscreen-close");


async function loadImageLists() {
    const response = await fetch("/api/image-lists");

    if (!response.ok) {
        throw new Error("Failed to load image lists");
    }

    imageLists = await response.json();

    const classes = Object.keys(imageLists).sort();

    classSelect.innerHTML = "";

    for (const className of classes) {
        const option = document.createElement("option");
        option.value = className;
        option.textContent = className;
        classSelect.appendChild(option);
    }

    if (classes.length > 0) {
        currentClass = classes[0];
        classSelect.value = currentClass;
        render();
    }
}


function createItem(item, modifiedOnly, originalSimilarity) {
    const element = document.createElement("div");
    element.className = "item";

    if (modifiedOnly) {
        element.classList.add("modified-only");
    }

    const wrapper = document.createElement("div");
    wrapper.className = "image-wrapper";

    const img = document.createElement("img");
    img.loading = "lazy";
    img.decoding = "async";
    img.src = "/image/" + encodeURIComponent(item.file);
    img.alt = item.file;

    wrapper.appendChild(img);
    element.appendChild(wrapper);

    const similarity = document.createElement("div");
    similarity.className = "similarity";
    similarity.textContent =
        Number(item.modified_similarity).toFixed(6);

    element.appendChild(similarity);

    element.addEventListener("mouseenter", (event) => {
        let tooltipText =
            `${item.file}<br>` +
            `modified similarity: ${Number(item.modified_similarity).toFixed(6)}`;

        if (!modifiedOnly) {
            tooltipText +=
                `<br>original similarity: ${Number(originalSimilarity).toFixed(6)}`;
        } else {
            tooltipText +=
                `<br>original similarity: ${Number(item.original_similarity).toFixed(6)}`;
        }

        tooltip.innerHTML = tooltipText;
        tooltip.style.display = "block";
        updateTooltipPosition(event);
    });

    element.addEventListener("mousemove", (event) => {
        updateTooltipPosition(event);
    });

    element.addEventListener("mouseleave", () => {
        tooltip.style.display = "none";
    });

    element.addEventListener("click", () => {
        fullscreenImage.src = img.src;
        fullscreen.style.display = "flex";
    });

    return element;
}


function updateTooltipPosition(event) {
    const offset = 12;
    const tooltipRect = tooltip.getBoundingClientRect();

    let left = event.clientX + offset;
    let top = event.clientY + offset;

    if (left + tooltipRect.width > window.innerWidth) {
        left = event.clientX - tooltipRect.width - offset;
    }

    if (top + tooltipRect.height > window.innerHeight) {
        top = event.clientY - tooltipRect.height - offset;
    }

    tooltip.style.left = `${left}px`;
    tooltip.style.top = `${top}px`;
}


function renderPanel(panel, grid, items, originalFiles, originalSimilarityMap) {
    grid.innerHTML = "";

    const columns = Math.max(
        1,
        Math.min(20, parseInt(columnsInput.value, 10) || 1)
    );

    grid.style.gridTemplateColumns =
        `repeat(${columns}, minmax(0, 1fr))`;

    let filteredItems = items;

    if (hidePerfectInput.checked) {
        filteredItems = items.filter(
            item => Number(item.modified_similarity) !== 1
        );
    }

    const sortedItems = [...filteredItems].sort(
        (a, b) =>
            Number(b.modified_similarity) -
            Number(a.modified_similarity)
    );

    for (const item of sortedItems) {
        const modifiedOnly =
            !originalFiles.has(item.file);

        const originalSimilarity =
            originalSimilarityMap.get(item.file);

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


function render() {
    if (!currentClass || !imageLists[currentClass]) {
        return;
    }

    const classResult = imageLists[currentClass];

    const original = classResult.original || [];
    const modified = classResult.all || [];

    const originalFiles = new Set(
        original.map(item => item.file)
    );

    const originalSimilarityMap = new Map(
        original.map(item => [
            item.file,
            Number(item.modified_similarity)
        ])
    );

    const originalCount = renderPanel(
        originalPanel,
        originalGrid,
        original,
        originalFiles,
        originalSimilarityMap
    );

    const modifiedCount = renderPanel(
        modifiedPanel,
        modifiedGrid,
        modified,
        originalFiles,
        originalSimilarityMap
    );

    originalHeader.textContent =
        `original (${originalCount})`;

    modifiedHeader.textContent =
        `modified (${modifiedCount})`;
}


classSelect.addEventListener("change", () => {
    currentClass = classSelect.value;

    originalPanel.scrollTop = 0;
    modifiedPanel.scrollTop = 0;

    render();
});


applyButton.addEventListener("click", () => {
    render();
});


window.addEventListener("resize", () => {
    render();
});


fullscreenClose.addEventListener("click", (event) => {
    event.stopPropagation();
    fullscreen.style.display = "none";
    fullscreenImage.src = "";
});


fullscreen.addEventListener("click", (event) => {
    if (event.target === fullscreen) {
        fullscreen.style.display = "none";
        fullscreenImage.src = "";
    }
});


document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
        fullscreen.style.display = "none";
        fullscreenImage.src = "";
    }
});


let syncingScroll = false;

originalPanel.addEventListener("scroll", () => {
    if (syncingScroll) {
        return;
    }

    syncingScroll = true;
    modifiedPanel.scrollTop = originalPanel.scrollTop;

    requestAnimationFrame(() => {
        syncingScroll = false;
    });
});


modifiedPanel.addEventListener("scroll", () => {
    if (syncingScroll) {
        return;
    }

    syncingScroll = true;
    originalPanel.scrollTop = modifiedPanel.scrollTop;

    requestAnimationFrame(() => {
        syncingScroll = false;
    });
});


loadImageLists().catch(error => {
    console.error(error);
});
</script>

</body>
</html>
"""


@app.get("/")
async def index():
    return HTMLResponse(HTML)


def main():
    parser = argparse.ArgumentParser(
        description="VOC image comparison viewer"
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

    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
    )


if __name__ == "__main__":
    main()
