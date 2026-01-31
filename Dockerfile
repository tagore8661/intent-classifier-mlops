# 1. Base Image
FROM python:3.10-slim

# 2. Set Environment Variables
# Prevents Python from writing pyc files to disc
ENV PYTHONDONTWRITEBYTECODE=1
# Prevents Python from buffering stdout and stderr
ENV PYTHONUNBUFFERED=1

# 3. Set Working Directory
WORKDIR /app

# 4. Copy Requirements
COPY requirements.txt .

# 5. Install Dependencies
# Update system dependencies and install python packages
# Note: Combining apt-get update/install and pip install reduces the number of layers and image size
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc libc-dev \
 && pip install --no-cache-dir -r requirements.txt \
 && apt-get remove -y gcc libc-dev \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

# 6. Copy Source Code
COPY . .

# 7. Train Model (Generate Artifacts)
RUN python3 model/train.py

# 8. Expose Port (Metadata only)
EXPOSE 6000

# 9. Start Application with Gunicorn
CMD ["gunicorn", "--workers", "4", "--bind", "0.0.0.0:6000", "app:app"]