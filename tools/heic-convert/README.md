# heic-convert

`heic_to_jpg.py` - convert HEIC/HEIF images to JPEG next to the original, for
the iPhone files that land on the SMB shares and open nowhere else. Takes files
or directories (recursive), or `--samba` for the shares
([`services/samba/README.md`](../../services/samba/README.md) - not the albums
share).

A `uv run --script` with its dependencies declared inline, so there is no venv
to manage: run the file directly.
