require("@nomiclabs/hardhat-waffle");
// require("@openzeppelin/hardhat-upgrades");
require("dotenv").config({ path: __dirname + "/.env" });

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const contractVersion = 3;

const config = {
  solidity: {
    compilers: [
      {
        version: "0.8.7",
      },
    ],
    settings: {
      optimizer: {
        enabled: true,
        runs: 2000,
      },
    },
  },
  paths: {
    sources: `./contracts/v${contractVersion}`,
  },
  networks: {
    ganache: {
      url: "HTTP://127.0.0.1:7545",
      accounts: {
        mnemonic:
          "tag palace accident hidden delay escape involve fetch mushroom corn settle doctor",
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        count: 10,
      },

      chainId: 1337,
    },
    polytest: {
      url: process.env.MUMBAI_ALCHEMY_URL || "",
      gas: 2100000,
      gasPrice: 8000000000,
      accounts: [`0x${process.env.MUMBAI_DEPLOYER_PRIV_KEY}`],
    },
  },
};

export default config;
