from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys
from typer import Option, Typer

app = Typer(no_args_is_help=True, pretty_exceptions_enable=False, help=__doc__)


@app.command()
def main(
    pg_host: str = Option(...),
    pg_port: int = 5432,
    pg_db: str = "headscale",
    pg_user: str = "headscale",
    pg_password: str = Option(...),
    sqlite_out: Path = Path("db.sqlite"),
):
    if not sqlite_out.exists():
        print(f'error: missing SQlite database file "{sqlite_out}" must already exists.', file=sys.stderr)
        print("       get it from an empty Headscale server run.", file=sys.stderr)
        sys.exit(1)

    # Load the convert.py from the vendored headscalebacktosqlite repository.
    convert = SourceFileLoader("convert", str(Path.cwd() / "vendor/headscalebacktosqlite/convert.py")).load_module()

    convert.POSTGRES_CONFIG = {
        "host": pg_host,
        "port": str(pg_port),
        "dbname": str(pg_db),
        "user": pg_user,
        "password": pg_password,
    }
    convert.SQLITE_DB_PATH = str(sqlite_out)

    convert.main()

    # Clean-up SQlite additional runtime files.
    if (file := sqlite_out.with_name(sqlite_out.name + "-shm")).exists():
        file.unlink()
    if (file := sqlite_out.with_name(sqlite_out.name + "-wal")).exists():
        file.unlink()


if __name__ == "__main__":
    app()
