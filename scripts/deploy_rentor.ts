import { sf } from "../superfluid_config.json";
import contractAddresses from "../contract_addresses.json";
import { logo } from "../ascii_logo";

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  // Rentor ------------------------------------------------------
  console.log(logo);
  console.log("Starting Rentor Deployment");
  const Rentor = await hre.ethers.getContractFactory("Rentor");
  const RentorInstance = await Rentor.deploy(
    sf.network.polytest.host,
    sf.network.polytest.cfa,
    sf.network.polytest.acceptedToken
  );
  await RentorInstance.deployed();
  const RentorAddress = RentorInstance.address;
  console.log(`Rentor deployed to : ${RentorAddress}`);

  // Saving contract address to file ----------------------------
  const contractAddress = JSON.stringify({
    ...contractAddresses,
    rentor: RentorAddress,
  });

  fs.writeFileSync(
    path.join(__dirname, "../contract_addresses.json"),
    contractAddress
  );
}

main()
  .then(() => console.log("Deployment Successful ✅"))
  .catch((error) => {
    console.error(error);
    console.log("Deployment Failed ❌");
  });
