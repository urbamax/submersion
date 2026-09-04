/// Suunto Nautic / Ocean dive events carry, alongside the generic
/// `dc_sample_event_t` the driver maps them to, the watch's own
/// `(sub-group << 8) | type` code in `event.value` (see the Nautic driver's
/// `suunto_nautic_map_event` and `SUUNTO_NAUTIC_PROTOCOL.md` §9.4). Decode it
/// back to the label the Suunto app shows, so a Nautic import keeps the exact
/// wording ("Ascent rate alarm") instead of the generic one ("Ascent Rate
/// Warning").
///
/// Returns `null` for an unknown code, or for a `value` that is not one of the
/// event sub-groups (e.g. a gas-mix index on a gas-switch event, or another
/// computer's `event.value`) — callers should also gate on the Suunto Nautic
/// vendor/product before trusting the result.
library;

const int _alarm = 0x18;
const int _warning = 0x19;
const int _notify = 0x1A;
const int _state = 0x1B;
const int _ooam = 0x1D;

String? suuntoNauticEventLabel(int? nativeValue) {
  if (nativeValue == null || nativeValue < 0) return null;
  final subGroup = (nativeValue >> 8) & 0xFF;
  final type = nativeValue & 0xFF;

  switch (subGroup) {
    case _alarm:
      return switch (type) {
        1 => 'Low ppO2 alarm',
        2 => 'High ppO2 alarm',
        3 => 'Tank pressure alarm',
        4 => 'Gas time alarm',
        5 => 'Ascent rate alarm',
        7 => 'CNS 100% alarm',
        8 => 'OTU 300 alarm',
        10 => 'Deco stop broken',
        12 => 'Deep stop broken',
        13 => 'Safety stop broken',
        31 => 'Depth alarm',
        50 => 'Battery alarm',
        _ => 'Alarm',
      };
    case _warning:
      return switch (type) {
        6 => 'High ppO2 warning',
        14 => 'CNS 80% warning',
        15 => 'OTU 250 warning',
        20 => 'Low no-deco time',
        28 => 'Tank pressure warning',
        29 => 'Gas time warning',
        30 => 'Sidemount warning',
        31 => 'Depth warning',
        32 => 'Dive time warning',
        42 => 'No-deco time warning',
        44 => 'Recovery time warning',
        50 => 'Battery warning',
        _ => 'Warning',
      };
    case _state:
      return switch (type) {
        19 => 'Decompression dive',
        35 => 'Deco stop reached',
        36 => 'Deep stop reached',
        37 => 'Safety stop reached',
        38 => 'Deco stop ahead',
        39 => 'Deep stop ahead',
        40 => 'Safety stop ahead',
        _ => null,
      };
    case _notify:
      return switch (type) {
        11 => 'Gas switch',
        21 => 'Setpoint switch',
        28 => 'Tank pressure notice',
        29 => 'Gas time notice',
        30 => 'Sidemount',
        31 => 'Depth notice',
        32 => 'Dive time',
        41 => 'Stop completed',
        42 => 'No-deco time notice',
        44 => 'Recovery time',
        60 => 'Bearing set',
        61 => 'Bearing cleared',
        62 => 'Stopwatch started',
        63 => 'Stopwatch reset',
        _ => null,
      };
    case _ooam:
      return switch (type) {
        1 => 'Out of battery',
        2 => 'Ceiling broken',
        3 => 'Software crash',
        4 => 'Max depth exceeded',
        5 => 'Algorithm changed',
        6 => 'Gauge dive',
        _ => null,
      };
    default:
      return null;
  }
}

/// Whether [vendor]/[product] name a Suunto Nautic-family computer whose
/// `event.value` should be run through [suuntoNauticEventLabel].
bool isSuuntoNauticFamily(String? vendor, String? product) =>
    vendor == 'Suunto' && (product == 'Nautic' || product == 'Ocean');
