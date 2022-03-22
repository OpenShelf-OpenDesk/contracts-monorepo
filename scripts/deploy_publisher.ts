import contractAddresses from "../contract_addresses.json";
import { logo } from "../ascii_logo";

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  // Publisher ------------------------------------------------------
  console.log(logo);
  console.log("Starting Publisher Deployment");
  const Publisher = await hre.ethers.getContractFactory("Publisher");
  const PublisherInstance = await Publisher.deploy();
  await PublisherInstance.deployed();
  const PublisherAddress = PublisherInstance.address;
  console.log(`Publisher deployed to : ${PublisherAddress}`);

  // Saving contract address to a file ----------------------------
  const contractAddress = JSON.stringify({
    ...contractAddresses,
    publisher: PublisherAddress,
  });

  fs.writeFileSync(
    path.join(__dirname, "..", "contract_addresses.json"),
    contractAddress
  );
}

main()
  .then(() => console.log("Deployment Successful ✅"))
  .catch((error) => {
    console.error(error);
    console.log("Deployment Failed ❌");
  });
