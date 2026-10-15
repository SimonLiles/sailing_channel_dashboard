"""U1 — Reusable SQL templates contract tests.

Verifies the CONTRACT of three SQL template files (file-content assertions
only, no DB needed):
- sql/00_utils/check_channel_exists.sql
- sql/01_raw/ops/insert_channel_dim.sql
- sql/01_raw/ops/reactivate_channel.sql

Architecture: placeholders ``{{project}}.{{dataset}}`` + BigQuery ``@named``
params; values are never interpolated.
"""

import os
import re

REPO_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..")
)

CHECK_SQL = os.path.join(
    REPO_ROOT, "sql", "00_utils", "check_channel_exists.sql"
)
INSERT_SQL = os.path.join(
    REPO_ROOT, "sql", "01_raw", "ops", "insert_channel_dim.sql"
)
REACTIVATE_SQL = os.path.join(
    REPO_ROOT, "sql", "01_raw", "ops", "reactivate_channel.sql"
)

ALL_SQL_FILES = [CHECK_SQL, INSERT_SQL, REACTIVATE_SQL]

PROJ = "test-proj"
DS = "test_ds"


def _read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def _render(text):
    return text.replace("{{project}}", PROJ).replace("{{dataset}}", DS)


def _strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    lines = [
        line.split("--", 1)[0]
        for line in text.splitlines()
    ]
    return "\n".join(lines)


def _assert_no_quoted_value_literals(text):
    body = _strip_comments(text)
    match = re.search(r"'[^']*'", body)
    assert match is None, (
        "value interpolation detected: single-quoted literal "
        f"{match.group(0)!r}; values must use @named params "
        "(only TRUE/FALSE/CURRENT_TIMESTAMP keywords allowed as literals)"
    )


# ---------------------------------------------------------------- existence

def test_check_channel_exists_file_exists():
    assert os.path.isfile(CHECK_SQL), f"missing {CHECK_SQL}"


def test_insert_channel_dim_file_exists():
    assert os.path.isfile(INSERT_SQL), f"missing {INSERT_SQL}"


def test_reactivate_channel_file_exists():
    assert os.path.isfile(REACTIVATE_SQL), f"missing {REACTIVATE_SQL}"


# ------------------------------------------------------- placeholder render

def test_check_placeholder_rendering():
    sql = _read(CHECK_SQL)
    rendered = _render(sql)
    assert "{{" not in rendered and "}}" not in rendered
    assert f"`{PROJ}.{DS}.channel_dimensions`" in rendered


def test_insert_placeholder_rendering():
    sql = _read(INSERT_SQL)
    rendered = _render(sql)
    assert "{{" not in rendered and "}}" not in rendered
    assert f"`{PROJ}.{DS}.channel_dimensions`" in rendered


def test_reactivate_placeholder_rendering():
    sql = _read(REACTIVATE_SQL)
    rendered = _render(sql)
    assert "{{" not in rendered and "}}" not in rendered
    assert f"`{PROJ}.{DS}.channel_dimensions`" in rendered


# ------------------------------------------------------- required named params

def test_check_requires_channel_id_param():
    sql = _read(CHECK_SQL)
    assert "@channel_id" in sql


def test_insert_requires_named_params():
    sql = _read(INSERT_SQL)
    for param in (
        "@channel_id",
        "@channel_handle",
        "@status",
        "@type",
        "@added_by",
    ):
        assert param in sql, f"missing required param {param}"


def test_reactivate_requires_channel_id_param():
    sql = _read(REACTIVATE_SQL)
    assert "@channel_id" in sql


# ------------------------------------------------------- no value interpolation

def test_check_no_value_interpolation():
    _assert_no_quoted_value_literals(_read(CHECK_SQL))


def test_insert_no_value_interpolation():
    _assert_no_quoted_value_literals(_read(INSERT_SQL))


def test_reactivate_no_value_interpolation():
    _assert_no_quoted_value_literals(_read(REACTIVATE_SQL))


# ------------------------------------------------------- statement shape

def test_check_selects_required_columns_with_where():
    sql = _read(CHECK_SQL)
    assert re.search(r"\bSELECT\b", sql, re.IGNORECASE)
    for col in ("channel_id", "channel_handle", "is_active"):
        assert re.search(
            r"\b" + col + r"\b", sql, re.IGNORECASE
        ), f"missing selected column {col}"
    assert re.search(
        r"`\{\{project\}\}\.\{\{dataset\}\}\.channel_dimensions`", sql
    ), "must select from `{{project}}.{{dataset}}.channel_dimensions`"
    assert re.search(
        r"WHERE\s+channel_id\s*=\s*@channel_id",
        sql,
        re.IGNORECASE,
    ), "must filter WHERE channel_id = @channel_id"


def test_insert_columns_values_and_timestamps():
    sql = _read(INSERT_SQL)
    assert re.search(r"\bINSERT\b", sql, re.IGNORECASE)
    for col in (
        "channel_id",
        "channel_handle",
        "is_active",
        "status",
        "type",
        "added_by",
        "created_at",
        "updated_at",
    ):
        assert re.search(
            r"\b" + col + r"\b", sql, re.IGNORECASE
        ), f"missing INSERT column {col}"
    assert re.search(
        r"`\{\{project\}\}\.\{\{dataset\}\}\.channel_dimensions`", sql
    )
    # is_active=TRUE literal.
    assert re.search(r"\bTRUE\b", sql), "INSERT must set is_active TRUE"
    # Both timestamps use CURRENT_TIMESTAMP().
    found = re.findall(
        r"CURRENT_TIMESTAMP\s*\(\s*\)", sql, re.IGNORECASE
    )
    assert len(found) >= 2, (
        "INSERT must set both created_at and updated_at "
        "to CURRENT_TIMESTAMP()"
    )


def test_reactivate_sets_active_true_with_false_guard():
    sql = _read(REACTIVATE_SQL)
    assert re.search(r"\bUPDATE\b", sql, re.IGNORECASE)
    assert re.search(
        r"`\{\{project\}\}\.\{\{dataset\}\}\.channel_dimensions`", sql
    )
    assert re.search(
        r"SET\b.*is_active\s*=\s*TRUE",
        sql,
        re.IGNORECASE | re.DOTALL,
    ), "must SET is_active=TRUE"
    assert re.search(
        r"SET\b.*updated_at\s*=\s*CURRENT_TIMESTAMP\s*\(\s*\)",
        sql,
        re.IGNORECASE | re.DOTALL,
    ), "must SET updated_at=CURRENT_TIMESTAMP()"
    assert re.search(
        r"WHERE\b.*channel_id\s*=\s*@channel_id",
        sql,
        re.IGNORECASE | re.DOTALL,
    ), "must filter WHERE channel_id = @channel_id"
    assert re.search(
        r"WHERE\b.*is_active\s*=\s*FALSE",
        sql,
        re.IGNORECASE | re.DOTALL,
    ), "must guard on is_active = FALSE"


# ------------------------------------------------------- layer header

def test_check_has_layer_header_comment():
    sql = _read(CHECK_SQL)
    assert "Layer:" in sql, "missing `Layer:` header comment line"


def test_insert_has_layer_header_comment():
    sql = _read(INSERT_SQL)
    assert "Layer:" in sql, "missing `Layer:` header comment line"


def test_reactivate_has_layer_header_comment():
    sql = _read(REACTIVATE_SQL)
    assert "Layer:" in sql, "missing `Layer:` header comment line"
