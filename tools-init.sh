#!/bin/bash

# -----------------------------------------------
cwd=$(pwd)
echo "-------------------------------------------------------------------------"
echo "Preparing your environment ..."

# Check for AWS Region --------------------------
export AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/\(.*\)[a-z]/\1/')
if [ -z "$AWS_REGION" ]
then
    # metadata might err, this is a safeguard
    echo "Error: AWS region not found, exiting"
    exit 0
else
    echo "Deploying into AWS region: ${AWS_REGION}"
fi

# Export Default Env Variables ------------------
if ! grep -q 'export AWS_REGION' ~/.bash_profile; then
    echo "export AWS_REGION=${AWS_REGION}" >> ~/.bash_profile
fi


aws configure set default.region ${AWS_REGION}
aws configure get default.region

export NVM_VER=$(curl --silent "https://github.com/nvm-sh/nvm/releases/latest" | sed 's#.*tag/\(.*\)\".*#\1#') #v.0.38.0
export SWB_VER=$(curl --silent "https://github.com/awslabs/service-workbench-on-aws/releases/latest" | sed 's#.*tag/\(.*\)\".*#\1#') #v.3.1.0
export PACKER_VER=1.7.2

# Ensure SWB code exists.  Assume it's the latest version. ------------
SWB_DIR=~/environment/service-workbench-on-aws
if [ -d $SWB_DIR ]; then
    cd $SWB_DIR
    CURRENT_VER=$(git describe --tags --abbrev=0)
    echo "SWB code ${CURRENT_VER} already installed"
else
    echo "Cloning SWB Repo ${SWB_VER} from GitHub into ~/environment"
    cd ~/environment
    git clone https://github.com/awslabs/service-workbench-on-aws.git >/dev/null 2>&1
fi
cd $cwd

DEPENDENCIES=(golang jq)
# echo "Installing dependencies ${DEPENDENCIES} ..."
for dependency in ${DEPENDENCIES[@]}; do
    if $(! yum list installed $dependency > /dev/null 2>&1); then
	echo "Installing dependency: $dependency"
	sudo yum install $dependency -y -q -e 0 >/dev/null 2>&1
    else
	echo "Dependency $dependency exists"
    fi
done

echo "Enabling utilities scripts ..."
chmod +x cloud9-resize.sh
chmod +x hosting-account/create-host-account.sh

DISKSIZE=$(df -m . | tail -1 | awk '{print $2}')
if (( DISKSIZE > 40000 )); then
    echo "Installation volume has adequate size: ${DISKSIZE} MB"
else
    echo "Resizing AWS Cloud9 Volume to 50 GB ..."    
    ./cloud9-resize.sh #50GB by default
fi

# NVM & Node Versions ---------------------------
# LTS_VER=$(nvm version-remote --lts)
source ~/.nvm/nvm.sh
if ! nvm --version > /dev/null 2>&1; then
    echo "Installing nvm ${NVM_VER} ..."
    rm -rf ~/.nvm
    export NVM_DIR=
    curl --silent -o- "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VER/install.sh" | bash
    source ~/.nvm/nvm.sh
else
    echo "nvm version $(nvm -v) is installed"
fi
exit

nvm install --lts
nvm use --lts
nvm alias default stable
node --version
echo "Exiting, check node version"
exit

# npm packages ----------------------------------
NPM_PACKAGES=(serverless pnpm hygen yarn docusaurus)
echo "Installing framework and libs ..."
npm install -g $NPM_PACKAGES >/dev/null 2>&1

# packer ----------------------------------------
echo "Installing packer ${PACKER_VER} into /usr/local/bin/ ..."
wget -q "https://releases.hashicorp.com/packer/$PACKER_VER/packer_${PACKER_VER}_linux_amd64.zip" -O packer_${PACKER_VER}_linux_amd64.zip
unzip "packer_${PACKER_VER}_linux_amd64.zip" >/dev/null 2>&1
sudo mv packer /usr/local/bin/ >/dev/null 2>&1
rm -f "packer_${PACKER_VER}_linux_amd64.zip" >/dev/null 2>&1

echo "Exiting"
exit

# finishing up ----------------------------------
echo "Finishing up ..."
echo -e "alias swb-ami-list='aws ec2 describe-images --owners self --query \"reverse(sort_by(Images[*].{Id:ImageId,Name:Name, Created:CreationDate}, &Created))\" --filters \"Name=name,Values=${STAGE_NAME}*\" --output table'" >> ~/.bashrc 
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" 
source ~/.bashrc 
echo ""
echo "Your AWS Cloud9 Environment is ready to use. "
echo "-------------------------------------------------------------------------"
