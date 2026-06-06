.import "DateUtils.js" as DateUtils

const fadedOpacity = 0.3

function draw(ctx, canvasWidth, canvasHeight, habits, today, cfg) {
    ctx.fillStyle = cfg.bg;
    ctx.fillRect(0, 0, canvasWidth, canvasHeight);

    ctx.save();
    ctx.translate(canvasWidth, 0);
    ctx.rotate(Math.PI / 2);

    const width = canvasHeight;
    const height = canvasWidth;

    drawContent(ctx, width, height, habits, today, cfg);

    ctx.restore();
}

const drawContent = (ctx, width, height, habits, today, cfg) => {
    const m = cfg.margin;
    let y = m;

    drawHeader(ctx, m, y, today, cfg);
    y += cfg.titleFont + 4 + cfg.subtitleFont + cfg.rowSpacing;

    const habitsX = m;
    const gridX = m + cfg.habitsWidth + cfg.buttonGap;

    const daysIn = DateUtils.daysInMonth(today);
    const currentDay = today.getDate();
    const year = today.getFullYear();
    const month = today.getMonth();

    drawDayLabels(ctx, gridX, y, daysIn, currentDay, cfg);
    y += cfg.dayLabelHeight + cfg.rowSpacing;

    const visible = habits.filter((h) => !h.hideFromSleep);

    for (let i = 0; i < visible.length; i++) {
        const habit = visible[i];
        drawHabitName(ctx, habitsX, y, habit.name, cfg);
        drawHabitCells(ctx, gridX, y, habit, daysIn, currentDay, year, month, cfg);
        y += cfg.boxSize + cfg.rowSpacing;
    }
};

const drawHeader = (ctx, x, y, today, cfg) => {
    ctx.fillStyle = cfg.fg;
    ctx.textAlign = "left";
    ctx.textBaseline = "top";

    ctx.font = `bold ${cfg.titleFont}px sans-serif`;
    ctx.fillText(DateUtils.monthName(today), x, y);

    ctx.font = `${cfg.subtitleFont}px sans-serif`;
    const days = DateUtils.daysInMonth(today);
    ctx.fillText(`${days} days · today is the ${DateUtils.ordinal(today.getDate())}`, x, y + cfg.titleFont + 4);
};

const drawDayLabels = (ctx, x, y, daysIn, currentDay, cfg) => {
    ctx.fillStyle = cfg.fg;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";

    for (let d = 1; d <= daysIn; d++) {
        const cellX = x + (d - 1) * (cfg.boxSize + cfg.boxSpacing);
        ctx.font = `${d === currentDay ? "bold " : ""}${cfg.dayLabelFont}px sans-serif`;
        ctx.fillText(d.toString(), cellX + cfg.boxSize / 2, y + cfg.dayLabelHeight / 2);
    }
};

const drawHabitName = (ctx, x, y, name, cfg) => {
    ctx.fillStyle = cfg.fg;
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.font = `${cfg.labelFont}px sans-serif`;
    ctx.fillText(name, x, y + cfg.boxSize / 2);
};

const drawHabitCells = (ctx, x, y, habit, daysIn, currentDay, year, month, cfg) => {
    const entries = habit.entries || {};

    for (let d = 1; d <= daysIn; d++) {
        const cellX = x + (d - 1) * (cfg.boxSize + cfg.boxSpacing);

        if (d === currentDay) {
            ctx.fillStyle = cfg.fg;
            ctx.fillRect(
                cellX - cfg.boxSpacing / 2,
                y - cfg.rowSpacing / 2,
                cfg.boxSize + cfg.boxSpacing,
                cfg.boxSize + cfg.rowSpacing
            );
        }

        ctx.fillStyle = cfg.bg;
        ctx.fillRect(cellX, y, cfg.boxSize, cfg.boxSize);
        ctx.strokeStyle = cfg.fg;
        ctx.lineWidth = cfg.borderWidth;
        ctx.strokeRect(cellX, y, cfg.boxSize, cfg.boxSize);

        const entry = entries[DateUtils.dateKey(year, month, d)] || "";
        const mark = entry === "x" ? "X" : entry === "o" ? "O" : habit.negative ? "X" : "";
        if (!mark) continue;

        const isFuture = d > currentDay;
        const faded = mark === "O" || isFuture;

        ctx.globalAlpha = faded ? fadedOpacity : 1.0;
        ctx.fillStyle = cfg.fg;
        ctx.font = `bold ${cfg.boxSize * 0.7}px sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(mark, cellX + cfg.boxSize / 2, y + cfg.boxSize / 2);
        ctx.globalAlpha = 1.0;
    }
};
