#!/bin/zsh

# Variables - Update these!
PROJECT_ID="your-gcp-project-id"
REGION="us-central1"
REPO="sailing-repo"
BASE_URL="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO"

echo "Starting Build & Push to Artifact Registry..."

# 1. Build and Push ETL Image
echo "Building ETL Image..."
docker build -t $BASE_URL/sailing-etl:latest -f Dockerfile.etl .
docker push $BASE_URL/sailing-etl:latest

# 2. Build and Push Shiny Image
echo "Building Shiny Image..."
docker build -t $BASE_URL/sailing-shiny:latest -f Dockerfile.shiny .
docker push $BASE_URL/sailing-shiny:latest

echo "Deployment complete!"