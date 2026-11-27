"""Inspect a browser-downloaded report and render every A4 page for visual QA."""
import argparse
import json
import sys
import unicodedata
from pathlib import Path

project_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(project_root / ".tools" / "python"))
import fitz

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("pdf", type=Path)
parser.add_argument("expected_total", nargs="?")
parser.add_argument("--independent-lengths", action="store_true",
                    help="Check the 150/95/160 m acceptance project and block calculations.")
args = parser.parse_args()
pdf_path = args.pdf.resolve()
expected_total = args.expected_total or ("50,844.50" if args.independent_lengths else "86,364.20")
document = fitz.open(pdf_path)
text = "\n".join(page.get_text() for page in document)
assert expected_total in text, f"Expected total {expected_total} not present in PDF"
assert len(document) >= 1
assert all(abs(page.rect.width - 595.28) < 1 for page in document)
assert all(abs(page.rect.height - 841.89) < 1 for page in document)
fonts = document[0].get_fonts(full=True)
assert len(fonts) >= 2
assert all(document.extract_font(font[0])[3] for font in fonts)
assert all("Cairo" in font[3] for font in fonts), fonts
if args.independent_lengths:
    # Arabic presentation forms and whitespace vary by PDF text extractor.
    compact = "".join(unicodedata.normalize("NFKC", text).split())
    measured_lengths = {
        "طول الميدة": 150,
        "طول مباني تحت الكتينة": 95,
        "طول مباني فوق الكتينة": 160,
    }
    for label, value in measured_lengths.items():
        row = f"{value}مترطولي{label.replace(' ', '')}"
        assert row in compact, f"Missing input row {label} = {value}"
    for formula in ["150×0.08=12", "95×10=950", "160×37.5=6,000"]:
        assert formula in compact, f"Missing calculated line {formula}"
png_paths = []
for index, page in enumerate(document):
    png_path = pdf_path.with_name(f"{pdf_path.stem}-page-{index + 1}.png")
    page.get_pixmap(matrix=fitz.Matrix(1.4, 1.4), alpha=False).save(png_path)
    png_paths.append(str(png_path))
summary = {
    "pdf": str(pdf_path),
    "bytes": pdf_path.stat().st_size,
    "pages": len(document),
    "size": [document[0].rect.width, document[0].rect.height],
    "expectedTotalFound": expected_total,
    "fontNames": [font[3] for font in fonts],
    "embeddedFonts": len(fonts),
    "pngs": png_paths,
}
pdf_path.with_suffix(".inspection.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(summary, ensure_ascii=False))
