#!/bin/sh

# Function to handle errors
handle_error() {
    echo "Error occurred in script execution. Exiting."
    exit 1
}

# Trap any error
trap 'handle_error' ERR

# Update and upgrade the system
echo "Updating and upgrading the system..."
sudo apt-get update && sudo apt-get upgrade -y
clear

# Install necessary packages and dependencies
echo "Installing necessary packages and dependencies..."
npm install --save-dev hardhat
npm install dotenv
npm install @swisstronik/utils
npm install @openzeppelin/contracts
npm install --save-dev @openzeppelin/hardhat-upgrades
npm install @nomicfoundation/hardhat-toolbox
npm install typescript ts-node @types/node
echo "Installation of dependencies completed."

# Create a new Hardhat project
echo "Creating a new Hardhat project..."
npx hardhat init

# Remove the default Lock.sol contract
echo "Removing default Lock.sol contract..."
rm -f contracts/Lock.sol

# Create .env file
echo "Creating .env file..."
read -p "Enter your private key: " PRIVATE_KEY
echo "PRIVATE_KEY=$PRIVATE_KEY" > .env
echo ".env file created."

# Configure Hardhat
echo "Configuring Hardhat..."
cat <<EOL > hardhat.config.ts
import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import dotenv from 'dotenv';
import '@openzeppelin/hardhat-upgrades';

dotenv.config();

const config: HardhatUserConfig = {
  defaultNetwork: 'swisstronik',
  solidity: '0.8.20',
  networks: {
    swisstronik: {
      url: 'https://json-rpc.testnet.swisstronik.com/',
      accounts: [\`0x\${process.env.PRIVATE_KEY}\`],
    },
  },
};

export default config;
EOL
echo "Hardhat configuration completed."

# Collect NFT contract details
read -p "Enter the NFT name: " NFT_NAME
read -p "Enter the NFT symbol: " NFT_SYMBOL

# Create the NFT contract
echo "Creating NFT.sol contract..."
mkdir -p contracts
cat <<EOL > contracts/NFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestNFT is ERC721 {
    uint256 private _currentTokenId = 0;

    event NFTMinted(address recipient, uint256 tokenId);

    constructor() ERC721("$NFT_NAME", "$NFT_SYMBOL") {}

    function mintNFT(address recipient) public returns (uint256) {
        _currentTokenId += 1;
        uint256 newItemId = _currentTokenId;
        _mint(recipient, newItemId);

        emit NFTMinted(recipient, newItemId);

        return newItemId;
    }

    function burnNFT(uint256 tokenId) public {
        _burn(tokenId);
    }
}
EOL
echo "NFT.sol contract created."

# Compile the contract
echo "Compiling the contract..."
npx hardhat compile
echo "Contract compiled."

# Create deploy.ts script
echo "Creating deploy.ts script..."
mkdir -p scripts
cat <<EOL > scripts/deploy.ts
import { ethers } from 'hardhat';
import fs from 'fs';
import path from 'path';

async function main() {
  const Contract = await ethers.getContractFactory('TestNFT');

  console.log('Deploying NFT...');
  const contract = await Contract.deploy();

  await contract.waitForDeployment();
  const contractAddress = await contract.getAddress();

  console.log('NFT deployed to:', contractAddress);

  const deployedAddressPath = path.join(__dirname, '..', 'utils', 'deployed-address.ts');

  const fileContent = \`const deployedAddress = '\${contractAddress}'\n\nexport default deployedAddress\n\`;

  fs.mkdirSync(path.join(__dirname, '..', 'utils'), { recursive: true });
  fs.writeFileSync(deployedAddressPath, fileContent, { encoding: 'utf8' });
  console.log('Address written to deployed-address.ts');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
EOL
echo "deploy.ts script created."

# Deploy the contract
echo "Deploying the contract..."
npx hardhat run scripts/deploy.ts --network swisstronik
echo "Contract deployed."

# Create mint.ts script
echo "Creating mint.ts script..."
mkdir -p utils
cat <<EOL > scripts/mint.ts
import { ethers, network } from 'hardhat';
import { encryptDataField } from '@swisstronik/utils';
import { HardhatEthersSigner } from '@nomicfoundation/hardhat-ethers/src/signers';
import { HttpNetworkConfig } from 'hardhat/types';
import * as fs from 'fs';
import * as path from 'path';
import deployedAddress from '../utils/deployed-address';

const sendShieldedTransaction = async (
  signer: HardhatEthersSigner,
  destination: string,
  data: string,
  value: number
) => {
  const rpclink = (network.config as HttpNetworkConfig).url;

  const [encryptedData] = await encryptDataField(rpclink, data);

  return await signer.sendTransaction({
    from: signer.address,
    to: destination,
    data: encryptedData,
    value,
  });
};

async function main() {
  const contractAddress = deployedAddress;

  const [signer] = await ethers.getSigners();

  const contractFactory = await ethers.getContractFactory('TestNFT');
  const contract = contractFactory.attach(contractAddress);

  const mintFunctionName = 'mintNFT';
  const recipientAddress = signer.address;
  const mintTx = await sendShieldedTransaction(
    signer,
    contractAddress,
    contract.interface.encodeFunctionData(mintFunctionName, [recipientAddress]),
    0
  );
  const mintReceipt = await mintTx.wait();
  console.log('Mint Transaction Hash: ', mintTx.hash);

  const mintEvent = mintReceipt?.logs
    .map((log) => {
      try {
        return contract.interface.parseLog(log);
      } catch (e) {
        return null;
      }
    })
    .find((event) => event && event.name === 'NFTMinted');
  const tokenId = mintEvent?.args?.tokenId;
  console.log('Minted NFT ID: ', tokenId.toString());

  const filePath = path.join(__dirname, '../utils/tx-hash.txt');
  fs.writeFileSync(filePath, \`NFT ID \${tokenId} : https://explorer-evm.testnet.swisstronik.com/tx/\${mintTx.hash}\n\`, {
    flag: 'a',
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOL
echo "mint.ts script created."

# Mint the NFT
echo "Minting NFT..."
npx hardhat run scripts/mint.ts --network swisstronik
echo "NFT minted."

echo "All operations completed successfully."
