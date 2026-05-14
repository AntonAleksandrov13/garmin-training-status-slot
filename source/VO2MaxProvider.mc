import Toybox.Lang;
import Toybox.Complications;
import Toybox.UserProfile;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Reads running VO2 max via the platform complication and maps it to one of
// Garmin's five fitness levels with the matching brand-ish color.
module VO2MaxProvider {

    enum {
        LVL_NONE      = -1,
        LVL_POOR      = 0,
        LVL_FAIR      = 1,
        LVL_GOOD      = 2,
        LVL_EXCELLENT = 3,
        LVL_SUPERIOR  = 4
    }

    function current() as Number? {
        if (!(Toybox has :Complications)) { return null; }
        try {
            var id = new Complications.Id(Complications.COMPLICATION_TYPE_VO2MAX_RUN);
            var c = Complications.getComplication(id);
            if (c == null || c.value == null) { return null; }
            var v = c.value;
            if (v instanceof Lang.Number) { return v as Number; }
            if (v instanceof Lang.Float)  { return (v as Float).toNumber(); }
            if (v instanceof Lang.String) {
                try { return (v as String).toNumber(); } catch (e) { return null; }
            }
        } catch (e) {}
        return null;
    }

    function levelFor(vo2 as Number) as Number {
        var prof = null;
        try { prof = UserProfile.getProfile(); } catch (e) {}
        var isMale = true;
        var age = 35;
        if (prof != null) {
            if (prof.gender != null) {
                isMale = (prof.gender == UserProfile.GENDER_MALE);
            }
            if (prof.birthYear != null) {
                var now = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
                age = (now.year as Number) - (prof.birthYear as Number);
                if (age < 10 || age > 99) { age = 35; }
            }
        }
        return classify(vo2, isMale, age);
    }

    // Color for the fitness level, matching Garmin's published palette.
    function colorFor(level as Number) as Number {
        if (level == LVL_POOR)      { return 0xFF3B30; }
        if (level == LVL_FAIR)      { return 0xFF9500; }
        if (level == LVL_GOOD)      { return 0x34C759; }
        if (level == LVL_EXCELLENT) { return 0x00C7FF; }
        if (level == LVL_SUPERIOR)  { return 0xAF52DE; }
        return 0xAAAAAA;
    }

    function labelFor(level as Number) as String {
        if (level == LVL_POOR)      { return "POOR"; }
        if (level == LVL_FAIR)      { return "FAIR"; }
        if (level == LVL_GOOD)      { return "GOOD"; }
        if (level == LVL_EXCELLENT) { return "EXCELLENT"; }
        if (level == LVL_SUPERIOR)  { return "SUPERIOR"; }
        return "";
    }

    // Garmin running VO2 max bands (rounded). Returns LVL_* based on age bucket + sex.
    function classify(v as Number, male as Boolean, age as Number) as Number {
        var t;
        if (male) {
            if (age < 30)      { t = [38, 42, 46, 51]; }
            else if (age < 40) { t = [35, 39, 44, 49]; }
            else if (age < 50) { t = [33, 37, 42, 47]; }
            else if (age < 60) { t = [31, 34, 40, 44]; }
            else if (age < 70) { t = [28, 31, 37, 41]; }
            else               { t = [26, 30, 34, 39]; }
        } else {
            if (age < 30)      { t = [31, 34, 37, 41]; }
            else if (age < 40) { t = [29, 32, 37, 40]; }
            else if (age < 50) { t = [27, 29, 34, 37]; }
            else if (age < 60) { t = [24, 27, 30, 34]; }
            else if (age < 70) { t = [23, 24, 27, 31]; }
            else               { t = [21, 23, 25, 29]; }
        }
        if (v < t[0]) { return LVL_POOR; }
        if (v < t[1]) { return LVL_FAIR; }
        if (v < t[2]) { return LVL_GOOD; }
        if (v < t[3]) { return LVL_EXCELLENT; }
        return LVL_SUPERIOR;
    }
}
