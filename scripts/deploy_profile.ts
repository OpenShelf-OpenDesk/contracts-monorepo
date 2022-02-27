import contractAddresses from "../contract_addresses.json";
import { logo } from "../ascii_logo";

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    // Profile ------------------------------------------------------
    console.log(logo);
    console.log("Starting Profile Deployment");
    const Profile = await hre.ethers.getContractFactory("Profile");
    const ProfileInstance = await Profile.deploy();
    await ProfileInstance.deployed();
    const ProfileAddress = ProfileInstance.address;
    console.log(`Profile deployed to : ${ProfileAddress}`);

    // Saving contract address to a file ----------------------------
    const contractAddress = JSON.stringify({
        ...contractAddresses,
        profile: ProfileAddress,
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
