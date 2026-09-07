#!/usr/bin/env python3
"""Read the Freelap developer fields out of a FIT file.

The watch's whole job is to put split times into the activity file, so the
question "did the fields actually land, with the right names, types and units"
is the one worth being able to answer without opening Garmin Connect (which
rounds floats in its UI and shows nothing at all if a field_description is
malformed).

    fit_fields.py <file.fit>              # the developer field table
    fit_fields.py <file.fit> --values     # and every message carrying one

Reads `field_description` messages for the declarations and `record`, `lap`
and `session` messages for the values. Needs `pip install fitdecode`.
"""
import sys

try:
    import fitdecode
except ImportError:  # pragma: no cover - exercised by the import guard test
    fitdecode = None

# Messages that can carry our developer fields, in the order they matter.
VALUE_MESSAGES = ("record", "lap", "session")


def _require_fitdecode():
    if fitdecode is None:
        raise SystemExit("pip install fitdecode")


def developer_fields(path):
    """The declared developer field table, in declaration order.

    Each entry: {number, name, type, units, mesg} — mesg is the message the
    field is attached to ('record', 'lap', 'session'), which is what
    native_mesg_num resolves to.
    """
    _require_fitdecode()
    out = []
    with fitdecode.FitReader(path) as fit:
        for frame in fit:
            if getattr(frame, "frame_type", None) != fitdecode.FIT_FRAME_DATA:
                continue
            if frame.name != "field_description":
                continue
            values = {f.name: f.value for f in frame.fields}
            out.append({
                "number": values.get("field_definition_number"),
                "name": values.get("field_name"),
                "type": values.get("fit_base_type_id"),
                "units": values.get("units"),
                "mesg": values.get("native_mesg_num"),
            })
    return out


def field_values(path, prefix="fl_"):
    """Every record/lap/session message that carries a developer field.

    Returns a list of (message_name, {field: value}) in file order, so a
    caller can assert on the *sequence* of splits, not just the last one.
    """
    _require_fitdecode()
    out = []
    with fitdecode.FitReader(path) as fit:
        for frame in fit:
            if getattr(frame, "frame_type", None) != fitdecode.FIT_FRAME_DATA:
                continue
            if frame.name not in VALUE_MESSAGES:
                continue
            values = {}
            for field in frame.fields:
                if field.name.startswith(prefix):
                    values[field.name] = field.value
            if values:
                out.append((frame.name, values))
    return out


def splits(path):
    """Just the record messages, as one dict per split, in order."""
    return [values for name, values in field_values(path) if name == "record"]


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    path = argv[1]

    print(f"{'#':>3}  {'name':<18} {'type':<8} {'units':<6} message")
    for field in developer_fields(path):
        units = field["units"] or ""
        print(f"{field['number']:>3}  {field['name']:<18} {field['type']:<8} {units:<6} {field['mesg']}")

    if "--values" in argv:
        print()
        for name, values in field_values(path):
            rendered = "  ".join(f"{k}={v}" for k, v in sorted(values.items()))
            print(f"{name:<8} {rendered}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
