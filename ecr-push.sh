#!/bin/bash

set -e

echo "Starting ECR deploy test..."

# Step 1: Check if ECR repo exists
echo "Step 1: Checking for ECR repository..."
REPO_NAME=$(awslocal ecr describe-repositories --region ap-southeast-1 --query 'repositories[0].repositoryName' --output text 2>/dev/null || echo "None")

if [ -z "$REPO_NAME" ] || [ "$REPO_NAME" = "None" ]; then
    echo "ERROR: No ECR repository found!"
    exit 1
fi

echo "Found ECR repository: $REPO_NAME"

# Get ECR repository URI
REPO_URI=$(awslocal ecr describe-repositories --region ap-southeast-1 --repository-names "$REPO_NAME" --query 'repositories[0].repositoryUri' --output text)
echo "Repository URI: $REPO_URI"

# Get cluster and service names
CLUSTER_NAME=$(awslocal ecs list-clusters --region ap-southeast-1 --query 'clusterArns[0]' --output text | awk -F'/' '{print $NF}')
SERVICE_NAME=$(awslocal ecs list-services --region ap-southeast-1 --cluster "$CLUSTER_NAME" --query 'serviceArns[0]' --output text | awk -F'/' '{print $NF}')

echo "ECS Cluster: $CLUSTER_NAME"
echo "ECS Service: $SERVICE_NAME"

# Step 2: Build and push Docker image
echo ""
echo "Step 2: Building and pushing Docker image..."
ECR_TAG="${REPO_URI}:latest"

docker build -f Dockerfile -t "${REPO_NAME}:latest" .
docker tag "${REPO_NAME}:latest" "${ECR_TAG}"

echo "Tagged image: ${ECR_TAG}"
docker images | grep -E "${REPO_NAME}|000000000000\.dkr\.ecr" || true

docker push "${ECR_TAG}"

echo "Image pushed successfully"

# Step 3: Force new deployment and get task ARN
echo ""
echo "Step 3: Forcing new deployment..."
awslocal ecs update-service \
    --region ap-southeast-1 \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --desired-count 1 \
    --force-new-deployment

# Wait for service to stabilize
echo "Waiting for service to stabilize..."
sleep 10

# Get Task ARN (only running tasks)
TASK_ARN_1=$(awslocal ecs list-tasks --region ap-southeast-1 --cluster "$CLUSTER_NAME" --service-name "$SERVICE_NAME" --desired-status RUNNING --query 'taskArns[0]' --output text)
echo "Task ARN: $TASK_ARN_1"

# Check task status
echo ""
echo "Checking task status..."
TASK_STATUS=$(awslocal ecs describe-tasks --region ap-southeast-1 --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN_1" --query 'tasks[0].lastStatus' --output text)
DESIRED_STATUS=$(awslocal ecs describe-tasks --region ap-southeast-1 --cluster "$CLUSTER_NAME" --tasks "$TASK_ARN_1" --query 'tasks[0].desiredStatus' --output text)
echo "Last Status: $TASK_STATUS"
echo "Desired Status: $DESIRED_STATUS"