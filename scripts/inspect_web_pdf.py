"""Inspect a browser-downloaded PDF and render its first A4 page for visual QA."""
import json
import sys
from pathlib import Path

project_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(project_root / ".tools" / "python"))
import fitz

pdf_path = Path(sys.argv[1]).resolve()
expected_total = sys.argv[2] if len(sys.argv) > 2 else "17,800"
document = fitz.open(pdf_path)
text = "\n".join(page.get_text() for page in document)
assert expected_total in text, f"Expected total {expected_total} not present in PDF"
assert len(document) == 1, f"Expected one-page report, found {len(document)} pages"
assert abs(document[0].rect.width - 595.28) < 1
assert abs(document[0].rect.height - 841.89) < 1
fonts = document[0].get_fonts(full=True)
assert len(fonts) >= 2
assert all(document.extract_font(font[0])[3] for font in fonts)
png_path = pdf_path.with_suffix(".png")
document[0].get_pixmap(matrix=fitz.Matrix(1.4, 1.4), alpha=False).save(png_path)
summary = {
    "pdf": str(pdf_path),
    "bytes": pdf_path.stat().st_size,
    "pages": len(document),
    "size": [document[0].rect.width, document[0].rect.height],
    "expectedTotalFound": expected_total,
    "fontNames": [font[3] for font in fonts],
    "embeddedFonts": len(fonts),
    "png": str(png_path),
}
pdf_path.with_suffix(".inspection.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(summary, ensure_ascii=False))
