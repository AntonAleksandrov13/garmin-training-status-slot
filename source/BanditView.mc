import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Lang;
import Toybox.System;
import Toybox.Math;
import Toybox.Timer;
import Toybox.Application;
import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.SensorHistory;
import Toybox.Weather;
import Toybox.Position;

class BanditView extends WatchUi.WatchFace {

    private const FRAME_MS as Number = 33;            // ~30fps
    private const ROW_HEIGHT as Number = 80;          // vertical size of each segment cell
    private const SPIN_BASE_MS as Number = 1600;      // first column stop
    private const SPIN_STAGGER_MS as Number = 700;    // gap between column stops
    private const FULL_ROTATIONS as Number = 4;

    private var _timer as Timer.Timer?;
    private var _spinning as Boolean = false;
    private var _waitingForStatus as Boolean = false;
    private var _realMode as Boolean = false;
    // Per-reel highlight after a scoring lock — segment text colored to the matched status.
    private var _rowHighlight as Array<Boolean> = [false, false, false] as Array<Boolean>;
    private var _highlightColor as Number = 0xFF3B30;
    private var _score as Number = 0;
    private var _lastAward as Number = 0;         // points awarded on the most recent lock

    // Per-row animation state
    private var _rowStart as Array<Number> = [0, 0, 0] as Array<Number>;
    private var _rowTarget as Array<Number> = [0, 0, 0] as Array<Number>;
    private var _rowDuration as Array<Number> = [0, 0, 0] as Array<Number>;
    private var _rowSpinStart as Array<Number> = [0, 0, 0] as Array<Number>;
    private var _rowOffset as Array<Number> = [0, 0, 0] as Array<Number>;
    private var _rowLocked as Array<Boolean> = [false, false, false] as Array<Boolean>;
    private var _rowLandedIdx as Array<Number> = [-1, -1, -1] as Array<Number>;

    function initialize() {
        WatchFace.initialize();
        var stored = Application.Storage.getValue("score");
        if (stored != null) { _score = stored as Number; }
    }

    function onLayout(dc as Dc) as Void {}

    function onShow() as Void {
        triggerSpin();
    }

    function onExitSleep() as Void {
        triggerSpin();
    }

    function onEnterSleep() as Void {
        stopTimer();
        _spinning = false;
        _waitingForStatus = false;
    }

    function triggerSpin() as Void {
        if (_spinning) { return; }
        _rowHighlight = [false, false, false] as Array<Boolean>;
        _lastAward = 0;

        var storage = Application.Storage;
        var count = storage.getValue("wakeCount");
        if (count == null) { count = 0; }
        count = (count as Number) + 1;
        storage.setValue("wakeCount", count);
        _realMode = ((count as Number) % 7) == 0;

        startSpin();
    }

    function startSpin() as Void {
        var symCount = TrainingStatusProvider.symbolCount();
        var stripH = symCount * ROW_HEIGHT;
        var now = System.getTimer();

        // Decide targets
        var realIdx = -1;
        _waitingForStatus = false;
        if (_realMode) {
            realIdx = TrainingStatusProvider.current();
            if (realIdx == TrainingStatusProvider.SYM_NONE) {
                _waitingForStatus = true;
            }
        }

        // Bias random spins: ~33% of non-real spins are "loaded" so all three reels
        // land on the same status (a 10-point match).
        var forcedIdx = -1;
        if (!(_realMode && realIdx != TrainingStatusProvider.SYM_NONE)) {
            if ((Math.rand() % 100) < 33) {
                forcedIdx = (Math.rand() % symCount) as Number;
            }
        }

        for (var i = 0; i < 3; i++) {
            var idx;
            if (_realMode && realIdx != TrainingStatusProvider.SYM_NONE) {
                idx = realIdx;
            } else if (forcedIdx >= 0) {
                idx = forcedIdx;
            } else {
                idx = (Math.rand() % symCount) as Number;
            }
            _rowLandedIdx[i] = idx;
            _rowStart[i] = _rowOffset[i];
            _rowDuration[i] = SPIN_BASE_MS + i * SPIN_STAGGER_MS;
            _rowSpinStart[i] = now;
            var landing = idx * ROW_HEIGHT;
            var minTarget = _rowStart[i] + FULL_ROTATIONS * stripH;
            var base = ((minTarget / stripH) + 1) * stripH;
            _rowTarget[i] = base + landing;
            _rowLocked[i] = false;
        }

        _spinning = true;
        if (_timer == null) { _timer = new Timer.Timer(); }
        _timer.start(method(:onTick), FRAME_MS, true);
    }

    function onTick() as Void {
        if (_spinning) {
            tickSpin();
        } else {
            stopTimer();
        }
    }

    function tickSpin() as Void {
        // If waiting for real status, keep all rows spinning at constant speed.
        if (_waitingForStatus) {
            var s = TrainingStatusProvider.current();
            if (s != TrainingStatusProvider.SYM_NONE) {
                var stripH2 = TrainingStatusProvider.symbolCount() * ROW_HEIGHT;
                var now2 = System.getTimer();
                for (var j = 0; j < 3; j++) {
                    _rowLandedIdx[j] = s;
                    _rowStart[j] = _rowOffset[j];
                    _rowDuration[j] = SPIN_BASE_MS + j * SPIN_STAGGER_MS;
                    _rowSpinStart[j] = now2;
                    var landing2 = s * ROW_HEIGHT;
                    var minT = _rowStart[j] + FULL_ROTATIONS * stripH2;
                    var base2 = ((minT / stripH2) + 1) * stripH2;
                    _rowTarget[j] = base2 + landing2;
                    _rowLocked[j] = false;
                }
                _waitingForStatus = false;
            } else {
                for (var k = 0; k < 3; k++) {
                    _rowOffset[k] += 14;
                }
                WatchUi.requestUpdate();
                return;
            }
        }

        var now = System.getTimer();
        var allLocked = true;
        for (var i = 0; i < 3; i++) {
            if (_rowLocked[i]) { continue; }
            var t = (now - _rowSpinStart[i]).toFloat() / _rowDuration[i].toFloat();
            if (t >= 1.0) {
                _rowOffset[i] = _rowTarget[i];
                _rowLocked[i] = true;
            } else {
                var inv = 1.0 - t;
                var eased = 1.0 - inv * inv * inv;
                _rowOffset[i] = (_rowStart[i] + (_rowTarget[i] - _rowStart[i]) * eased).toNumber();
                allLocked = false;
            }
        }

        if (allLocked) {
            _spinning = false;
            evaluateScore();
            stopTimer();
        }
        WatchUi.requestUpdate();
    }

    function evaluateScore() as Void {
        _lastAward = 0;
        _rowHighlight = [false, false, false] as Array<Boolean>;
        if (_rowLandedIdx[0] < 0) { return; }

        // Compare displayed segment text (not landed indices) so visually-equivalent
        // reels like a shared "ING" / "TIVE" count toward word recognition.
        var segs = TrainingStatusProvider.segments();
        var s0 = segs[0][_rowLandedIdx[0]];
        var s1 = segs[1][_rowLandedIdx[1]];
        var s2 = segs[2][_rowLandedIdx[2]];
        var concat = s0 + s1 + s2;
        var n = TrainingStatusProvider.symbolCount();

        // 10 points: the three reels read as any real status name.
        for (var i = 0; i < n; i++) {
            if (concat.equals(TrainingStatusProvider.fullLabel(i))) {
                _lastAward = 10;
                _rowHighlight = [true, true, true] as Array<Boolean>;
                _highlightColor = TrainingStatusProvider.colorFor(i);
                _score += _lastAward;
                Application.Storage.setValue("score", _score);
                return;
            }
        }

        // 5 points (suffix): reels 1+2 read as the suffix of a status with a readable suffix.
        var suf = s1 + s2;
        for (var i = 0; i < n; i++) {
            if (TrainingStatusProvider.hasReadableSuffix(i)
                    && (segs[1][i] + segs[2][i]).equals(suf)) {
                _lastAward = 5;
                _rowHighlight = [false, true, true] as Array<Boolean>;
                _highlightColor = TrainingStatusProvider.colorFor(i);
                _score += _lastAward;
                Application.Storage.setValue("score", _score);
                return;
            }
        }

        // 5 points (prefix): reels 0+1 read as the prefix of a status with a readable prefix.
        var pre = s0 + s1;
        for (var i = 0; i < n; i++) {
            if (TrainingStatusProvider.hasReadablePrefix(i)
                    && (segs[0][i] + segs[1][i]).equals(pre)) {
                _lastAward = 5;
                _rowHighlight = [true, true, false] as Array<Boolean>;
                _highlightColor = TrainingStatusProvider.colorFor(i);
                _score += _lastAward;
                Application.Storage.setValue("score", _score);
                return;
            }
        }
    }

    function stopTimer() as Void {
        if (_timer != null) { _timer.stop(); }
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Slot bbox
        var totalW = (w * 0.94).toNumber();
        var colW = totalW / 3;
        var reelH = ROW_HEIGHT;
        var startX = ((w - totalW) / 2).toNumber();
        var startY = ((h - reelH) / 2).toNumber();

        dc.setColor(0x303030, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(startX - 6, startY - 6, totalW + 12, reelH + 12, 12);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(startX, startY, totalW, reelH, 8);

        for (var i = 0; i < 3; i++) {
            var x = startX + i * colW;
            drawColumn(dc, x, startY, colW, reelH, i);
            if (i < 2) {
                dc.setColor(0x202020, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x + colW, startY + 4, x + colW, startY + reelH - 4);
            }
        }

        drawHeader(dc, w, startY);
        drawDataFields(dc, w, h, startX, startY, totalW, reelH);

    }

    function drawHeader(dc as Dc, w as Number, slotTopY as Number) as Void {
        var clock = System.getClockTime();
        var timeStr = clock.hour.format("%02d") + ":" + clock.min.format("%02d");
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, slotTopY - 92, Graphics.FONT_NUMBER_MEDIUM, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var now = Time.Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = (now.day_of_week as String).toUpper() + " " + now.day.format("%d");
        var stats = System.getSystemStats();
        var battPct = stats.battery.toNumber();
        var battColor = 0xFFCC00;
        if (battPct < 20) { battColor = 0xFF3B30; }
        else if (battPct > 60) { battColor = 0x34C759; }

        var tempStr = readTemperature();
        var sunsetStr = readSunset();

        var rowY = slotTopY - 40;
        var battStr = battPct.format("%d") + "%";

        // Three evenly-spread cells, each self-centered on its anchor
        var anchors = [w / 2 - 100, w / 2, w / 2 + 100];

        drawCell(dc, anchors[0], rowY, :thermometer, 0xFF9500,
                 tempStr != null ? tempStr : "--", Graphics.COLOR_WHITE);
        // Center cell: date (no icon)
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(anchors[1], rowY, Graphics.FONT_XTINY, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        drawCell(dc, anchors[2], rowY, :battery, battColor, battStr, Graphics.COLOR_WHITE);

        // Sunset on a small line above the slot, centered
        if (sunsetStr != null) {
            drawCellCentered(dc, w / 2, slotTopY - 8, :sun, 0xFF9500, sunsetStr, Graphics.COLOR_WHITE);
        }
    }

    // Draw a (icon + value) cell whose overall width is centered on (cx, cy).
    function drawCell(dc as Dc, cx as Number, cy as Number, kind as Symbol,
                      iconColor as Number, value as String, textColor as Number) as Void {
        drawCellCentered(dc, cx, cy, kind, iconColor, value, textColor);
    }

    function drawCellCentered(dc as Dc, cx as Number, cy as Number, kind as Symbol,
                              iconColor as Number, value as String, textColor as Number) as Void {
        var iconW = 14;
        var gap = 6;
        var textW = dc.getTextWidthInPixels(value, Graphics.FONT_XTINY);
        var totalW = iconW + gap + textW;
        var iconCx = cx - totalW / 2 + iconW / 2;
        var textX = iconCx + iconW / 2 + gap;
        drawIcon(dc, kind, iconCx, cy, iconColor);
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, cy, Graphics.FONT_XTINY, value,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawIcon(dc as Dc, kind as Symbol, cx as Number, cy as Number, color as Number) as Void {
        if (kind == :thermometer) { Icons.thermometer(dc, cx, cy, 14, color); }
        else if (kind == :battery) {
            var stats = System.getSystemStats();
            Icons.battery(dc, cx, cy, 18, color, stats.battery.toNumber());
        }
        else if (kind == :sun)     { Icons.sun(dc, cx, cy, 12, color); }
        else if (kind == :floors)  { Icons.floors(dc, cx, cy, 14, color); }
        else if (kind == :heart)   { Icons.heart(dc, cx, cy, 14, color); }
        else if (kind == :bolt)    { Icons.bolt(dc, cx, cy, 14, color); }
        else if (kind == :steps)   { Icons.steps(dc, cx, cy, 14, color); }
    }

    function readTemperature() as String? {
        if (!(Toybox has :Weather)) { return null; }
        try {
            var cc = Weather.getCurrentConditions();
            if (cc == null || cc.temperature == null) { return null; }
            var t = cc.temperature as Number;
            var ds = System.getDeviceSettings();
            if (ds.temperatureUnits == System.UNIT_STATUTE) {
                t = (t * 9 / 5 + 32);
            }
            return t.format("%d") + "°";
        } catch (e) { return null; }
    }

    function readSunset() as String? {
        if (!(Toybox has :Weather)) { return null; }
        try {
            var cc = Weather.getCurrentConditions();
            if (cc == null || cc.observationLocationPosition == null) { return null; }
            var pos = cc.observationLocationPosition as Position.Location;
            var degs = pos.toDegrees();
            var lat = degs[0] as Float;
            var lon = degs[1] as Float;
            var now = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
            var sunsetMin = computeSunsetUtcMinutes(now.year as Number, now.month as Number,
                now.day as Number, lat, lon);
            if (sunsetMin == null) { return null; }
            // Convert UTC minutes-of-day to local using device's clock offset
            var clock = System.getClockTime();
            var localOffsetSec = clock.timeZoneOffset as Number;
            var localMin = (sunsetMin + localOffsetSec / 60) % (24 * 60);
            if (localMin < 0) { localMin += 24 * 60; }
            var hh = (localMin / 60).toNumber();
            var mm = (localMin % 60).toNumber();
            return hh.format("%02d") + ":" + mm.format("%02d");
        } catch (e) { return null; }
    }

    // NOAA-ish sunset solar calc. Returns UTC minutes-of-day of sunset, or null on degenerate cases.
    function computeSunsetUtcMinutes(year as Number, month as Number, day as Number,
                                      lat as Float, lon as Float) as Number? {
        var PI = Math.PI as Float;
        var rad = PI / 180.0;
        var n1 = (275 * month / 9).toNumber();
        var n2 = ((month + 9) / 12).toNumber();
        var n3 = (1 + ((year - 4 * (year / 4) + 2) / 3).toNumber());
        var N = n1 - (n2 * n3) + day - 30;
        var lngHour = lon / 15.0;
        var t = N + ((18.0 - lngHour) / 24.0);                     // sunset rising time approx
        var M = (0.9856 * t) - 3.289;                              // sun mean anomaly
        var L = M + (1.916 * Math.sin(M * rad)) + (0.020 * Math.sin(2.0 * M * rad)) + 282.634;
        L = normDeg(L);
        var RA = Math.atan(0.91764 * Math.tan(L * rad)) / rad;
        RA = normDeg(RA);
        var Lq = ((L / 90.0).toNumber()) * 90;
        var RAq = ((RA / 90.0).toNumber()) * 90;
        RA = RA + (Lq - RAq);
        RA = RA / 15.0;
        var sinDec = 0.39782 * Math.sin(L * rad);
        var cosDec = Math.cos(Math.asin(sinDec));
        var zenith = 90.833;
        var cosH = (Math.cos(zenith * rad) - (sinDec * Math.sin(lat * rad))) / (cosDec * Math.cos(lat * rad));
        if (cosH > 1.0 || cosH < -1.0) { return null; }            // sun never rises/sets
        var H = Math.acos(cosH) / rad;                             // sunset uses positive
        H = H / 15.0;
        var T = H + RA - (0.06571 * t) - 6.622;
        var UT = T - lngHour;
        UT = UT - (24.0 * (UT / 24.0).toNumber());
        if (UT < 0.0) { UT += 24.0; }
        return (UT * 60.0).toNumber();
    }

    function normDeg(d as Float) as Float {
        var n = d - (360.0 * (d / 360.0).toNumber());
        if (n < 0.0) { n += 360.0; }
        return n;
    }

    function drawDataFields(dc as Dc, w as Number, h as Number, slotX as Number, slotY as Number,
                            slotW as Number, slotH as Number) as Void {
        var info = ActivityMonitor.getInfo();
        var act = Activity.getActivityInfo();

        var hr = "--";
        if (act != null && act.currentHeartRate != null) {
            hr = (act.currentHeartRate as Number).toString();
        }
        var bb = readBodyBattery();
        var steps = "--";
        if (info != null && info.steps != null) {
            steps = formatThousands(info.steps as Number);
        }
        var floors = "--";
        if (info != null && (info has :floorsClimbed) && info.floorsClimbed != null) {
            floors = (info.floorsClimbed as Number).toString();
        }
        // Data row directly below the slot.
        var bottomY = slotY + slotH + 28;
        var span = (w * 0.78).toNumber();
        var x0 = (w - span) / 2;
        var step = span / 3;

        drawCellCentered(dc, x0 + 0 * step, bottomY, :floors, 0xFFCC00, floors, Graphics.COLOR_WHITE);
        drawCellCentered(dc, x0 + 1 * step, bottomY, :heart,  0xFF3B30, hr,     Graphics.COLOR_WHITE);
        drawCellCentered(dc, x0 + 2 * step, bottomY, :bolt,   0x00C7FF, bb,     Graphics.COLOR_WHITE);
        drawCellCentered(dc, x0 + 3 * step, bottomY, :steps,  0x34C759, steps,  Graphics.COLOR_WHITE);

        // VO2 Max big number under the metrics row, color = Garmin fitness level.
        drawVO2Max(dc, w / 2, bottomY + 50);

        // Current bandit score under the VO2 max line.
        drawScore(dc, w / 2, bottomY + 84);
    }

    function drawScore(dc as Dc, cx as Number, cy as Number) as Void {
        var label = "SCORE";
        var value = _score.toString();
        var gap = 6;
        var labelW = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY);
        var valueW = dc.getTextWidthInPixels(value, Graphics.FONT_XTINY);
        var totalW = labelW + gap + valueW;
        var leftX = cx - totalW / 2;

        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX, cy, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        // Recent award color: gold for 10, green for 5, white otherwise.
        var color = Graphics.COLOR_WHITE;
        if (_lastAward == 10) { color = 0xFFCC00; }
        else if (_lastAward == 5) { color = 0x34C759; }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + labelW + gap, cy, Graphics.FONT_XTINY, value,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function drawVO2Max(dc as Dc, cx as Number, cy as Number) as Void {
        var v = VO2MaxProvider.current();
        if (v == null) { return; }
        var level = VO2MaxProvider.levelFor(v as Number);
        var color = VO2MaxProvider.colorFor(level);
        var num = (v as Number).toString();
        var label = "VO2";
        var gap = 6;
        var numW = dc.getTextWidthInPixels(num, Graphics.FONT_NUMBER_MILD);
        var labelW = dc.getTextWidthInPixels(label, Graphics.FONT_XTINY);
        var totalW = labelW + gap + numW;
        var leftX = cx - totalW / 2;

        // Dim label on the left
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX, cy + 6, Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        // Number right of label
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(leftX + labelW + gap, cy, Graphics.FONT_NUMBER_MILD, num,
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function readBodyBattery() as String {
        if (!(Toybox has :SensorHistory)) { return "--"; }
        try {
            if (Toybox.SensorHistory has :getBodyBatteryHistory) {
                var it = Toybox.SensorHistory.getBodyBatteryHistory({ :period => 1 });
                if (it != null) {
                    var sample = it.next();
                    if (sample != null && sample.data != null) {
                        return (sample.data as Number).format("%d");
                    }
                }
            }
        } catch (e) {}
        return "--";
    }

    function formatThousands(n as Number) as String {
        if (n < 1000) { return n.toString(); }
        var k = n / 1000;
        var r = (n % 1000) / 100;
        return k.toString() + "." + r.toString() + "k";
    }

    function drawColumn(dc as Dc, x as Number, y as Number, colW as Number, colH as Number, col as Number) as Void {
        var symCount = TrainingStatusProvider.symbolCount();
        var stripH = symCount * ROW_HEIGHT;
        var segs = TrainingStatusProvider.segments()[col];

        var off = _rowOffset[col];
        if (off < 0) { off = 0; }
        var localOffset = off % stripH;

        var topSegIdx = (localOffset / ROW_HEIGHT).toNumber() % symCount;
        var topYWithinWindow = -(localOffset % ROW_HEIGHT);

        dc.setClip(x, y, colW, colH);

        var cx = x + colW / 2;
        for (var k = 0; k < 2; k++) {
            var segIdx = (topSegIdx + k) % symCount;
            var segY = y + topYWithinWindow + k * ROW_HEIGHT;
            var textCy = segY + ROW_HEIGHT / 2;
            var highlighted = !_spinning && _rowHighlight[col] && segIdx == _rowLandedIdx[col];
            dc.setColor(highlighted ? _highlightColor : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, textCy, Graphics.FONT_MEDIUM, segs[segIdx],
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        dc.clearClip();
    }
}
