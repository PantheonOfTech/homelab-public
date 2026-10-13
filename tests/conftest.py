"""Load the standalone scripts in Code/Python as importable modules for the tests."""
import importlib.util
import pathlib

import pytest

PY_DIR = pathlib.Path(__file__).resolve().parent.parent / "Code" / "Python"


def _load(name):
    spec = importlib.util.spec_from_file_location(name, PY_DIR / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def cuairt():
    return _load("cuairt")


@pytest.fixture(scope="session")
def seala():
    return _load("seala")
