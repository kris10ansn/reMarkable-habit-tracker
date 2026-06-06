const clampScroll = (x, max) => Math.max(0, Math.min(max, x));

function scrollByBoxes(currentX, boxes, step, max) {
    return clampScroll(currentX + boxes * step, max);
}

function centerOnDay(day, viewport, boxSize, boxSpacing, max) {
    const step = boxSize + boxSpacing;
    const target = (day - 1) * step - viewport / 2 + boxSize / 2;
    return clampScroll(target, max);
}
