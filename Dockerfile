FROM python:3.13-slim

WORKDIR /app

# System deps (fonts needed for reportlab PDF generation with custom fonts)
RUN apt-get update && apt-get install -y --no-install-recommends \
    fontconfig \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Snapshot the default data files (choices.json, guinea_admin.json,
# price_matrix.json, empty photos/ tree) BEFORE the persistent disk is
# mounted over /app/data at container start. A Render disk mounted at
# /app/data arrives EMPTY on first boot and hides everything baked into
# the image at that path - entrypoint.sh restores anything missing from
# this snapshot without ever overwriting real data already on the disk.
RUN cp -r /app/data /app/data_seed
RUN chmod +x /app/entrypoint.sh

# Persist the SQLite database and JSON data files across deploys via a volume
VOLUME ["/app/data"]

ENV PORT=5070
EXPOSE 5070

# gunicorn production server: 2 workers, 120s timeout for PDF/Excel generation
CMD ["/app/entrypoint.sh"]
