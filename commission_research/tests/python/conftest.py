"""Make pipeline/ and tools/ importable and give the license tools a test secret."""

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "commission_research" / "pipeline"))
sys.path.insert(0, str(ROOT / "tools"))

os.environ["MADLANGA_LICENSE_SECRET"] = "test-secret"
