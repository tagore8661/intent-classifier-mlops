# AWS CloudShell Deployment : Scalable Intent Classifier

This guide provides a robust, step-by-step workflow to deploy the Intent Classifier application on AWS. We will build a complete infrastructure stack - Virtual Private Cloud (VPC), Auto Scaling Group (ASG), and Application Load Balancer (ALB) - using the **AWS CloudShell**.

### Overview of Architecture
We will deploy:
1.  **Networking**: A custom VPC with Public Subnets across two Availability Zones for high availability.
2.  **Compute**: EC2 instances launching automatically via a Launch Template.
3.  **Routing**: An Application Load Balancer to distribute traffic to our healthy instances.

---

### 1. CloudShell & AMI Setup
First, ensure you are operating in the strictly defined region and locate the base operating system image.

**Set Region**
CloudShell usually initializes this, but we explicitly set it to avoid errors.
```bash
export AWS_REGION=$(aws configure get region)
echo "Deploying to Region: $AWS_REGION"
```

**Identify Ubuntu 20.04 AMI**
We query AWS for the official Ubuntu 20.04 server image ID. We limit the search to the "focal" release to ensure compatibility.
```bash
aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate)[-1].ImageId' \
    --output text \
    --region $AWS_REGION
```

**Action**: Copy the output ID from above and export it.
```bash
export AMI_ID="<PASTE_AMI_ID_HERE>"
```

### 2. Network Infrastructure (VPC & Subnets)
We need a custom network. An Application Load Balancer **requires** subnets in at least two different zones (e.g., `us-east-1a` and `us-east-1b`) to ensure it survives a data center failure.

**Initialize VPC**
This creates the isolated network space `10.10.0.0/16`.
```bash
aws ec2 create-vpc --cidr-block 10.10.0.0/16 --query 'Vpc.VpcId' --output text --region $AWS_REGION
```
**Action**: Export the VPC ID.
```bash
export VPC_ID="<PASTE_VPC_ID_HERE>"
```

**Create Multi-AZ Subnets**
We create two public subnets.

*Subnet 1 (Zone A)*:
```bash
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.10.1.0/24 --availability-zone ${AWS_REGION}a --query 'Subnet.SubnetId' --output text --region $AWS_REGION
```
**Action**: Export Subnet 1 ID.
```bash
export SUBNET_ID1="<PASTE_SUBNET_ID1_HERE>"
```

*Subnet 2 (Zone B)*:
```bash
aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.10.2.0/24 --availability-zone ${AWS_REGION}b --query 'Subnet.SubnetId' --output text --region $AWS_REGION
```
**Action**: Export Subnet 2 ID.
```bash
export SUBNET_ID2="<PASTE_SUBNET_ID2_HERE>"
```

### 3. Internet Connectivity
By default, a VPC is private. We must attach a gateway to allow traffic in and out.

**Create & Attach Gateway**
```bash
# Create Gateway
aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region $AWS_REGION
```
**Action**: Export Gateway ID.
```bash
export IGW_ID="<PASTE_IGW_ID_HERE>"
```

**Connect Gateway to VPC**
```bash
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION
```

**Configure Routing**
Traffic destined for the internet (`0.0.0.0/0`) must be directed to the Gateway.
```bash
# Create Route Table
aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $AWS_REGION
```
**Action**: Export Route Table ID.
```bash
export RTB_ID="<PASTE_RTB_ID_HERE>"
```

**Apply Routes**
```bash
# Add rule: All external traffic -> Internet Gateway
aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $AWS_REGION

# Associate table with our subnets
aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_ID1 --region $AWS_REGION
aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SUBNET_ID2 --region $AWS_REGION
```

**Enable Public IPs**
This ensures instances in these subnets automatically get a public IP address, which makes debugging easier.
```bash
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_ID2 --map-public-ip-on-launch
```

### 4. Security Firewall
We need to define a "firewall" (Security Group) that permits web traffic and SSH access.

```bash
aws ec2 create-security-group --group-name intent-sg --description "Allow app and ssh" --vpc-id $VPC_ID --query 'GroupId' --output text --region $AWS_REGION
```
**Action**: Export Security Group ID.
```bash
export SG_ID="<PASTE_SG_ID_HERE>"
```

**Open Ports**
```bash
# Open Port 80 (HTTP)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $AWS_REGION

# Open Port 22 (SSH)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $AWS_REGION
```

### 5. Fetch Source Code & User Data
We need the correct startup script (`user-data.sh`). **Crucially**, this script resides in a specific git branch (`virtual-machines`). We *must* checkout that branch to access it.

```bash
git clone https://github.com/tagore8661/intent-classifier-mlops.git
cd intent-classifier-mlops

# MANDATORY: Switch to the branch containing the infrastructure scripts
git checkout virtual-machines
```

### 6. Create Launch Template
The Launch Template acts as a blueprint for every server the Auto Scaling Group creates.

**Why Base64?**
The AWS CLI accepts the `UserData` parameter inside a JSON object. If we passed plain text script code (which contains newlines, quotes, and symbols), it would break the JSON formatting. Encoding it in **Base64** converts the script into a safe, single-line alphanumeric string that the API can transport without corruption.

**Prepare Configuration**
```bash
# 1. Encode the startup script safely
USER_DATA=$(base64 -w0 user-data.sh)

# 2. Define the exact hardware template
export LAUNCH_TEMPLATE_NAME="mlops-template"
export INSTANCE_TYPE="t3.micro"
export KEY_NAME="mlops-keypair" 
# NOTE: Make sure 'mlops-keypair' exists in your EC2 Key Pairs!
```

**Execute Creation**
```bash
aws ec2 create-launch-template \
  --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
  --version-description "v1" \
  --launch-template-data "{\"ImageId\":\"$AMI_ID\",\"InstanceType\":\"$INSTANCE_TYPE\",\"KeyName\":\"$KEY_NAME\",\"SecurityGroupIds\":[\"$SG_ID\"],\"UserData\":\"$USER_DATA\"}" \
  --region $AWS_REGION
```

### 7. Load Balancing (ALB & Target Groups)
The Load Balancer needs a place to send traffic. We call this a "Target Group".

**Create Target Group**
We define a group that listens on Port 80 and checks `/health` to ensure the app is running.
```bash
aws elbv2 create-target-group \
  --name mlops-target-group \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --health-check-protocol HTTP \
  --health-check-path /health \
  --matcher HttpCode=200 \
  --region $AWS_REGION
```
**Action**: Export Target Group ARN.
```bash
export TARGET_GROUP_ARN="<PASTE_TARGET_GROUP_ARN_HERE>"
```

**Deploy Load Balancer**
We launch the ALB across our two public subnets.
```bash
aws elbv2 create-load-balancer \
  --name model-deployment \
  --subnets $SUBNET_ID1 $SUBNET_ID2 \
  --security-groups $SG_ID \
  --scheme internet-facing \
  --type application \
  --region $AWS_REGION
```
**Action**: Export ALB ARN.
```bash
export ALB_ARN="<PASTE_ALB_ARN_HERE>"
```

**Attach Listener**
This connects the ALB to the Target Group. "Forward any traffic hitting Port 80 on the ALB to the Target Group".
```bash
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP_ARN \
  --region $AWS_REGION
```

### 8. Auto Scaling Group (ASG)
Finally, we create the engine that manages our instances. This ASG will:
1.  Read the Blueprint (Launch Template).
2.  Launch instances into our Subnets.
3.  Register them with the Target Group automatically.

**Create ASG**
```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name mlops-autoscaling \
  --launch-template LaunchTemplateName=mlops-template,Version=1 \
  --min-size 1 --max-size 3 --desired-capacity 1 \
  --vpc-zone-identifier "$SUBNET_ID1,$SUBNET_ID2" \
  --region $AWS_REGION
```

**Link to Load Balancer**
This command explicitly tells the ASG: "Whenever you launch a new VM, register it with this Load Balancer Target Group immediately."
```bash
aws autoscaling attach-load-balancer-target-groups \
  --auto-scaling-group-name mlops-autoscaling \
  --target-group-arns "$TARGET_GROUP_ARN" \
  --region $AWS_REGION
```

### 9. Verification
To verify the deployment, retrieve your Load Balancer's DNS name and send a test request.

**Get ALB DNS Name:**
```bash
aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --query 'LoadBalancers[0].DNSName' --output text --region $AWS_REGION
```

**Open Local Terminal** and run the curl command (replace `<ALB-DNS-NAME>` with the output from above):

```bash
# Test a Greeting
curl -X POST http://<ALB-DNS-NAME>/predict \
     -H "Content-Type: application/json" \
     -d '{"text": "Hello, how are you?"}'
```

---

## Destroy Infrastructure (Manual Cleanup)
To avoid ongoing costs, follow these steps to manually delete all resources in the AWS Console. **Order is critical** to avoid dependency errors.

#### 1. Auto Scaling Group (ASG)
The ASG manages the EC2 instances. It must be stopped first.
1.  Go to **EC2 Console** -> **Auto Scaling Groups**.
2.  Select `mlops-autoscaling`.
3.  **Detach Target Groups**:
    *   Go to **Instance management** (or Integration) tab.
    *   Find Load Balancing / Target Groups in the details.
    *   **Edit** and uncheck/remove the target group.
4.  **Scale Down**:
    *   Go to **Details** -> **Edit**.
    *   Set **Desired**, **Minimum**, and **Maximum** capacity to **0**.
    *   *Update*.
5.  **Delete ASG**:
    *   Select the ASG -> **Delete**.
    *   Confirm force delete if prompted.
    *   *This will automatically terminate the instances.*

#### 2. EC2 Instances
Ensure all instances are gone.
1.  Go to **EC2 Dashboard** -> **Instances**.
2.  If any instances remain (e.g., stuck in "Stopped"), select them.
3.  **Instance State** -> **Terminate Instance**.

#### 3. Application Load Balancer (ALB)
The ALB cannot be deleted if it has active listeners in some configurations, but usually, deleting the ALB cascades.
1.  Go to **Load Balancers**.
2.  Select `model-deployment`.
3.  **Actions** -> **Delete Load Balancer**.
4.  Wait for the state to disappear or confirm deletion.

#### 4. Target Groups
1.  Go to **Target Groups**.
2.  Select `mlops-target-group`.
3.  **Actions** -> **Delete**.
    *   *Note: If it fails, ensure the ALB is fully deleted first.*

#### 5. Launch Template
1.  Go to **Launch Templates**.
2.  Select `mlops-template`.
3.  **Actions** -> **Delete Template**.

#### 6. Security Groups
1.  Go to **Security Groups**.
2.  Delete **ALB Security Group** (if you created a separate one).
3.  Delete **Instance Security Group** (`intent-sg`).
    *   *If deletion fails:* Check if any "Network Interfaces" are still using it. Wait a moment for terminated instances to fully release their interfaces.

#### 7. Subnets
1.  Go to **VPC Console** -> **Subnets**.
2.  Select the two subnets created (check the VPC ID match).
3.  **Actions** -> **Delete Subnet**.

#### 8. Internet Gateway (IGW)
1.  Go to **Internet Gateways**.
2.  Select the gateway attached to your VPC.
3.  **Actions** -> **Detach from VPC**.
4.  Once detached, **Actions** -> **Delete Internet Gateway**.

#### 9. VPC
1.  Go to **Your VPCs**.
2.  Select the specific VPC created for this project.
3.  **Actions** -> **Delete VPC**.
    *   *Note: This usually cleans up the Route Table and Network ACLs automatically.*