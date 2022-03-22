import contractAddresses from "../contract_addresses.json";
import { logo } from "../ascii_logo";

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  // Exchange ------------------------------------------------------
  console.log(logo);
  console.log("Starting Exchange Deployment");
  const Exchange = await hre.ethers.getContractFactory("Exchange");
  const ExchangeInstance = await hre.upgrades.deployProxy(Exchange, []);
  await ExchangeInstance.deployed();
  const ExchangeAddress = ExchangeInstance.address;
  console.log(`Exchange deployed to : ${ExchangeAddress}`);

  // saving contract address to a file ----------------------------
  const contractAddress = JSON.stringify({
    ...contractAddresses,
    exchange: ExchangeAddress,
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
