import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from app import validate_username


def test_valid_username():
    assert validate_username("alice") == True


def test_username_with_number_start():
    assert validate_username("1alice") == False


def test_empty_username_rejected():
    assert validate_username("") == False
