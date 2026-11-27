/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 *
 * Small line graph of download and upload speed. Repaints only while visible.
 */
import QtQuick

Canvas {
    id: graph

    property var downData: []
    property var upData: []
    property int capacity: 60          // samples across the full width
    property color downColor: "#3daee9"
    property color upColor: "#f67400"
    property real fillOpacity: 0.25
    property real lineWidth: 1.5
    // Highest value of the visible data (bytes per second), for a label
    readonly property double maximum: {
        let top = 0;
        for (const v of downData) { top = Math.max(top, v); }
        for (const v of upData) { top = Math.max(top, v); }
        return top;
    }

    onDownDataChanged: if (visible) requestPaint()
    onUpDataChanged: if (visible) requestPaint()
    onVisibleChanged: if (visible) requestPaint()
    onWidthChanged: if (visible) requestPaint()
    onHeightChanged: if (visible) requestPaint()

    // Draws one curve (download or upload) with a faint fill below it; top = the value at the upper edge
    function drawSeries(ctx: var, data: var, color: color, top: double): void {
        if (data.length < 2) {
            return;
        }
        const step = width / Math.max(1, capacity - 1);
        const start = width - (data.length - 1) * step;   // newest sample at the right edge
        const y = v => height - (v / top) * (height - lineWidth) - lineWidth / 2;

        ctx.beginPath();
        ctx.moveTo(start, y(data[0]));
        for (let i = 1; i < data.length; ++i) {
            ctx.lineTo(start + i * step, y(data[i]));
        }
        ctx.strokeStyle = color;
        ctx.lineWidth = lineWidth;
        ctx.globalAlpha = 1;
        ctx.stroke();

        ctx.lineTo(width, height);
        ctx.lineTo(start, height);
        ctx.closePath();
        ctx.fillStyle = color;
        ctx.globalAlpha = fillOpacity;
        ctx.fill();
        ctx.globalAlpha = 1;
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);
        const top = Math.max(1024, maximum);
        drawSeries(ctx, downData, downColor, top);
        drawSeries(ctx, upData, upColor, top);
    }
}
