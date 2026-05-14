import Toybox.Lang;
import Toybox.WatchUi;
import Toybox.Complications;

module TrainingStatusProvider {

    enum {
        SYM_NONE         = -1,
        SYM_PRODUCTIVE   = 0,
        SYM_UNPRODUCTIVE = 1,
        SYM_MAINTAINING  = 2,
        SYM_RECOVERY     = 3,
        SYM_DETRAINING   = 4,
        SYM_PEAKING      = 5,
        SYM_OVERREACHING = 6,
        SYM_STRAINED     = 7,
        SYM_NO_STATUS    = 8
    }

    function symbolCount() as Number { return 9; }

    // 3-row split of each status. Reading top->mid->bot spells the word.
    // Index by [row][symbol].
    function segments() as Array<Array<String>> {
        return [
            ["PRO",  "UNPR", "MAIN", "RE",  "DE",    "PE", "OVER",  "STR", "NO"],
            ["DUC",  "ODUC", "TAIN", "COV", "TRAIN", "AK", "REACH", "AIN", "STA"],
            ["TIVE", "TIVE", "ING",  "ERY", "ING",   "ING","ING",   "ED",  "TUS"]
        ] as Array<Array<String>>;
    }

    // Garmin-ish color per training status.
    function colorFor(sym as Number) as Number {
        switch (sym) {
            case SYM_PRODUCTIVE:   return 0x34C759;  // green
            case SYM_MAINTAINING:  return 0x00C7FF;  // blue
            case SYM_RECOVERY:     return 0x5AC8FA;  // light blue
            case SYM_PEAKING:      return 0xFF9500;  // orange
            case SYM_OVERREACHING: return 0xFF6A00;  // deep orange
            case SYM_UNPRODUCTIVE: return 0xFFCC00;  // amber
            case SYM_DETRAINING:   return 0xAF52DE;  // purple
            case SYM_STRAINED:     return 0xFF3B30;  // red
            case SYM_NO_STATUS:    return 0xAAAAAA;  // grey
        }
        return 0xFFFFFF;
    }

    // Whitelist of "readable" 2-segment partials per status.
    // hasReadablePrefix(sym): col0+col1 reads as a real word (e.g. PEAK, MAINTAIN, OVERREACH).
    // hasReadableSuffix(sym): col1+col2 reads as a real word (e.g. TRAINING, REACHING, STATUS).
    function hasReadablePrefix(sym as Number) as Boolean {
        // PRODUC, UNPRODUC, MAINTAIN, DETRAIN, PEAK, OVERREACH, STRAIN
        return sym == SYM_PRODUCTIVE
            || sym == SYM_UNPRODUCTIVE
            || sym == SYM_MAINTAINING
            || sym == SYM_DETRAINING
            || sym == SYM_PEAKING
            || sym == SYM_OVERREACHING
            || sym == SYM_STRAINED;
    }
    function hasReadableSuffix(sym as Number) as Boolean {
        // TRAINING, REACHING, STATUS
        return sym == SYM_DETRAINING
            || sym == SYM_OVERREACHING
            || sym == SYM_NO_STATUS;
    }

    function fullLabel(sym as Number) as String {
        var segs = segments();
        if (sym < 0 || sym >= symbolCount()) { return ""; }
        return segs[0][sym] + segs[1][sym] + segs[2][sym];
    }

    function current() as Number {
        if (!(Toybox has :Complications)) { return SYM_NONE; }
        var raw = readComplication();
        if (raw == null) { return SYM_NONE; }
        if (raw instanceof Lang.String) { return matchLabel(raw as String); }
        if (raw instanceof Lang.Number) {
            switch (raw as Number) {
                case 0: return SYM_NO_STATUS;
                case 1: return SYM_RECOVERY;
                case 2: return SYM_MAINTAINING;
                case 3: return SYM_PRODUCTIVE;
                case 4: return SYM_PEAKING;
                case 5: return SYM_OVERREACHING;
                case 6: return SYM_UNPRODUCTIVE;
                case 7: return SYM_DETRAINING;
                case 8: return SYM_STRAINED;
            }
        }
        return SYM_NONE;
    }

    function readComplication() {
        try {
            var id = new Complications.Id(Complications.COMPLICATION_TYPE_TRAINING_STATUS);
            var c = Complications.getComplication(id);
            if (c == null) { return null; }
            return c.value;
        } catch (e) {
            return null;
        }
    }

    function matchLabel(s as String) as Number {
        var u = s.toUpper();
        if (u.find("UNPRODUCTIVE") != null) { return SYM_UNPRODUCTIVE; }
        if (u.find("PRODUCTIVE") != null)   { return SYM_PRODUCTIVE; }
        if (u.find("MAINTAIN") != null)     { return SYM_MAINTAINING; }
        if (u.find("RECOVERY") != null)     { return SYM_RECOVERY; }
        if (u.find("DETRAIN") != null)      { return SYM_DETRAINING; }
        if (u.find("PEAK") != null)         { return SYM_PEAKING; }
        if (u.find("OVERREACH") != null)    { return SYM_OVERREACHING; }
        if (u.find("STRAIN") != null)       { return SYM_STRAINED; }
        if (u.find("NO STATUS") != null)    { return SYM_NO_STATUS; }
        return SYM_NONE;
    }
}
