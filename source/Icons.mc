import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Tiny vector icons drawn with dc primitives. All icons render inside an
// (size x size) bounding box centered at (cx, cy). Pass the color you want.
module Icons {

    function heart(dc as Dc, cx as Number, cy as Number, size as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var r = size / 4;
        var lx = cx - r;
        var rx = cx + r;
        var topY = cy - r / 2;
        dc.fillCircle(lx, topY, r);
        dc.fillCircle(rx, topY, r);
        var pts = [
            [cx - 2 * r, topY] as [Number, Number],
            [cx + 2 * r, topY] as [Number, Number],
            [cx, cy + size / 2] as [Number, Number]
        ];
        dc.fillPolygon(pts);
    }

    function steps(dc as Dc, cx as Number, cy as Number, size as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var s = size / 2;
        // Two ovals offset like footprints
        dc.fillRoundedRectangle(cx - s, cy - s / 2, s - 2, s + 2, 3);
        dc.fillRoundedRectangle(cx + 2, cy - s / 2 + s / 2, s - 2, s + 2, 3);
        // toe dots
        dc.fillCircle(cx - s + (s - 2) / 2, cy - s, 1);
        dc.fillCircle(cx + 2 + (s - 2) / 2, cy, 1);
    }

    function floors(dc as Dc, cx as Number, cy as Number, size as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var s = size;
        var x = cx - s / 2;
        var y = cy + s / 2 - 2;
        var step = s / 3;
        // three rising stairs
        dc.fillRectangle(x,           y - 2,           step + 1, 2);
        dc.fillRectangle(x + step,    y - step,        step + 1, 2);
        dc.fillRectangle(x + 2*step,  y - 2*step,      step + 1, 2);
        // verticals
        dc.fillRectangle(x,            y - 2,           1, 2);
        dc.fillRectangle(x + step,     y - step,        1, step);
        dc.fillRectangle(x + 2*step,   y - 2*step,      1, step);
        dc.fillRectangle(x + 3*step,   y - 2*step,      1, 2*step);
    }

    function bolt(dc as Dc, cx as Number, cy as Number, size as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var h = size;
        var w = size * 2 / 3;
        var pts = [
            [cx - 1,        cy - h / 2] as [Number, Number],
            [cx + w / 2,    cy - h / 2] as [Number, Number],
            [cx,            cy] as [Number, Number],
            [cx + w / 2,    cy] as [Number, Number],
            [cx - 1,        cy + h / 2] as [Number, Number],
            [cx + 1,        cy + 1] as [Number, Number],
            [cx - w / 2,    cy + 1] as [Number, Number]
        ];
        dc.fillPolygon(pts);
    }

    function battery(dc as Dc, cx as Number, cy as Number, size as Number, color as Number,
                     pct as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var w = size;
        var h = (size * 3 / 5);
        if (h < 6) { h = 6; }
        var x = cx - w / 2;
        var y = cy - h / 2;
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(x, y, w, h, 2);
        // nub
        dc.fillRectangle(x + w, y + h / 4, 2, h / 2);
        // fill
        var fillW = ((w - 4) * pct / 100).toNumber();
        if (fillW < 0) { fillW = 0; }
        if (fillW > w - 4) { fillW = w - 4; }
        dc.fillRectangle(x + 2, y + 2, fillW, h - 4);
    }

    function sun(dc as Dc, cx as Number, cy as Number, size as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var r = size / 4;
        dc.fillCircle(cx, cy, r);
        var rays = size / 2;
        dc.setPenWidth(1);
        // 8 short rays
        dc.drawLine(cx - rays, cy,        cx - r - 1, cy);
        dc.drawLine(cx + r + 1, cy,       cx + rays, cy);
        dc.drawLine(cx, cy - rays,        cx, cy - r - 1);
        dc.drawLine(cx, cy + r + 1,       cx, cy + rays);
        var d = (rays * 7) / 10;
        var dr = (r + 1) * 7 / 10;
        dc.drawLine(cx - d, cy - d,   cx - dr, cy - dr);
        dc.drawLine(cx + dr, cy - dr, cx + d, cy - d);
        dc.drawLine(cx - d, cy + d,   cx - dr, cy + dr);
        dc.drawLine(cx + dr, cy + dr, cx + d, cy + d);
    }

    function thermometer(dc as Dc, cx as Number, cy as Number, size as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var h = size;
        var stemW = 3;
        var bulbR = 4;
        var topY = cy - h / 2;
        dc.fillRoundedRectangle(cx - stemW / 2, topY, stemW, h - bulbR, 2);
        dc.fillCircle(cx, cy + h / 2 - bulbR, bulbR);
    }

    function envelope(dc as Dc, cx as Number, cy as Number, size as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var w = size;
        var h = size * 2 / 3;
        var x = cx - w / 2;
        var y = cy - h / 2;
        dc.setPenWidth(1);
        dc.drawRectangle(x, y, w, h);
        dc.drawLine(x, y, cx, cy);
        dc.drawLine(cx, cy, x + w, y);
    }
}
