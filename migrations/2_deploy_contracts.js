const Remittance = artifacts.require("Remittance");
const { toBN, toWei } = web3.utils;

module.exports = function(deployer) {
  deployer.deploy(
    Remittance,
    toBN(toWei("0.05", "ether")),
    toBN(60 * 60 * 24), // 1 day
    toBN(60 * 60 * 24 * 7) // 7 days
  );
};
