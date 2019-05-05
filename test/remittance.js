const truffleAssert = require("truffle-assertions");
const { eventEmitted, reverts } = truffleAssert;
const { toBN, toWei } = web3.utils;
const { getBalance } = web3.eth;
const Remittance = artifacts.require("Remittance");

contract("Remittance", async accounts => {
  const BN_0 = toBN("0");
  const BN_1GW = toBN(toWei("1", "gwei"));
  const BN_HGW = toBN(toWei("0.5", "gwei"));
  const ZEROx0 = "0x0000000000000000000000000000000000000000";

  const [ALICE, BOB, CAROL, SOMEONE] = accounts;

  const REMITTANCE = await Remittance.deployed();

  describe("Function: constructor", async () => {
    it("should have deployer as pauser", async () => {
      const isPauser = await REMITTANCE.isPauser(ALICE, { from: ALICE });
      assert.isTrue(isPauser, "deployer is not pauser");
    });

    it("should have initial balance of zero", async () => {
      const balance = toBN(await getBalance(REMITTANCE.address));
      assert(balance.eq(BN_0), "contract balance is not zero");
    });
  });

  describe("Function: fallback", async () => {
    it("should revert on fallback", async () => {
      await reverts(REMITTANCE.sendTransaction({ from: ALICE, value: BN_1GW }));
    });
  });
});
