const uuidv4 = require("uuid/v4");
const truffleHelper = require("./helpers/truffleTestHelper");
const { advanceTime } = truffleHelper;
const truffleAssert = require("truffle-assertions");
const { createTransactionResult, eventEmitted, reverts } = truffleAssert;
const { toBN, toWei, asciiToHex } = web3.utils;
const { getBalance } = web3.eth;
const Remittance = artifacts.require("Remittance");

contract("Remittance", accounts => {
  const BN_0 = toBN("0");
  const BN_1ETH = toBN(toWei("1", "ether"));
  const BN_HETH = toBN(toWei("0.5", "ether"));
  const BN_FEE = toBN(toWei("0.05", "ether"));
  const FAKE_ID = asciiToHex("FAKE ID");
  const BN_LT_MIN = toBN(60 * 60 * 12); // 12 hours in secs
  const BN_MIN = toBN(60 * 60 * 24); // 24 hours in secs
  const BN_DEADLINE = toBN(60 * 60 * 24 * 3); // 3 days in secs
  const DEADLINE_MS = 60 * 60 * 24 * 3 * 1000; // 3 days in msecs
  const BN_MAX = toBN(60 * 60 * 24 * 7); // 7 days in secs
  const BN_GT_MAX = toBN(60 * 60 * 24 * 14); // 14 days in secs
  const ZEROx0 = "0x0000000000000000000000000000000000000000";

  const [ALICE, BOB, CAROL, SOMEONE] = accounts;
  let REMITTANCE;

  beforeEach("Initialization", async () => {
    REMITTANCE = await Remittance.new(BN_FEE, BN_MIN, BN_MAX, { from: ALICE });
  });

  describe("Function: constructor", () => {
    it("should have initial balance of zero", async () => {
      const balance = toBN(await getBalance(REMITTANCE.address));
      assert(balance.eq(BN_0), "contract balance is not zero");
    });

    it("should have emmitted fee set event", async () => {
      const result = await createTransactionResult(
        REMITTANCE,
        REMITTANCE.transactionHash
      );
      await eventEmitted(result, "RemittanceFeeSet", log => {
        return log.by === ALICE && log.fee.eq(BN_FEE);
      });
    });

    it("should set remittance fee accordingly", async () => {
      const fee = await REMITTANCE.fee({ from: ALICE });
      assert.isTrue(fee.eq(BN_FEE), "remittance fee mismatch");
    });
  });

  describe("Contract: Ownable", () => {
    it("should have deployer as owner", async () => {
      const isOwner = await REMITTANCE.isOwner({ from: ALICE });
      assert.isTrue(isOwner, "deployer is not owner");
    });

    it("should reject other account as owner", async () => {
      const isOwner = await REMITTANCE.isOwner({ from: BOB });
      assert.isFalse(isOwner, "deployer is owner");
    });
  });

  describe("Contract: Pausable", () => {
    it("should have deployer as pauser", async () => {
      const isPauser = await REMITTANCE.isPauser(ALICE, { from: ALICE });
      assert.isTrue(isPauser, "deployer is not pauser");
    });

    it("should reject other account as pauser", async () => {
      const isPauser = await REMITTANCE.isPauser(BOB, { from: ALICE });
      assert.isFalse(isPauser, "deployer is pauser");
    });
  });

  describe("Function: fallback", () => {
    it("should revert on fallback", async () => {
      await reverts(
        REMITTANCE.sendTransaction({ from: ALICE, value: BN_1ETH })
      );
    });
  });

  describe("Function: fee getter and setter", () => {
    it("should change fee", async () => {
      const result = await REMITTANCE.setFee(BN_HETH, { from: ALICE });
      await eventEmitted(result, "RemittanceFeeSet", log => {
        return log.by === ALICE && log.fee.eq(BN_HETH);
      });
      const fee = await REMITTANCE.fee({ from: ALICE });
      assert.isTrue(fee.eq(BN_HETH), "remittance fee mismatch");
    });
  });

  describe("Function: deadline range getter and setter", () => {
    it("should change range", async () => {
      const result = await REMITTANCE.setDeadlineRange(BN_DEADLINE, BN_GT_MAX, {
        from: ALICE
      });
      await eventEmitted(result, "RemittanceDeadlineRangeSet", log => {
        return (
          log.by === ALICE && log.min.eq(BN_DEADLINE) && log.max.eq(BN_GT_MAX)
        );
      });
      const range = await REMITTANCE.deadlineRange({ from: ALICE });
      assert.isTrue(range.min.eq(BN_DEADLINE), "range min mismatch");
      assert.isTrue(range.max.eq(BN_GT_MAX), "range max mismatch");
    });
  });

  describe("Function: transfer", () => {
    it("should revert on invalid recipient", async () => {
      await reverts(
        REMITTANCE.transfer(FAKE_ID, ZEROx0, BN_DEADLINE, {
          from: ALICE
        }),
        "invalid recipient"
      );
    });

    it("should revert on previous remittance", async () => {
      await REMITTANCE.transfer(FAKE_ID, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_HETH
      });
      await reverts(
        REMITTANCE.transfer(FAKE_ID, BOB, BN_DEADLINE, {
          from: ALICE,
          value: BN_HETH
        }),
        "previous remittance"
      );
    });

    it("should revert on value less than fee", async () => {
      await reverts(
        REMITTANCE.transfer(FAKE_ID, BOB, BN_DEADLINE, {
          from: ALICE,
          value: BN_0
        }),
        "value less than fee"
      );
    });

    it("should revert on deadline out of range (LT min)", async () => {
      await reverts(
        REMITTANCE.transfer(FAKE_ID, BOB, BN_LT_MIN, {
          from: ALICE,
          value: BN_HETH
        }),
        "deadline out of range"
      );
    });

    it("should revert on deadline out of range (GT max)", async () => {
      await reverts(
        REMITTANCE.transfer(FAKE_ID, BOB, BN_GT_MAX, {
          from: ALICE,
          value: BN_HETH
        }),
        "deadline out of range"
      );
    });

    it("should start remittance (transfer)", async () => {
      const secret = new Array();
      uuidv4(null, secret, 0);
      const id = await REMITTANCE.generateRemittanceId(
        REMITTANCE.address,
        ALICE,
        BOB,
        secret
      );
      const balance1a = toBN(await getBalance(REMITTANCE.address));
      const balance2a = toBN(await getBalance(ALICE));
      const result = await REMITTANCE.transfer(id, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_1ETH
      });
      await eventEmitted(result, "RemittanceTransferred", log => {
        return (
          log.remittanceId === id &&
          log.sender === ALICE &&
          log.recipient === BOB &&
          BN_1ETH.sub(BN_FEE).eq(log.amount) &&
          BN_FEE.eq(log.fee)
          // Won't check deadline because it cannot
          // be calculated outside the contract due to
          // block.timestamp (which can also differ by 15s).
        );
      });
      const balance1b = toBN(await getBalance(REMITTANCE.address));
      assert.isTrue(
        balance1b.sub(balance1a).eq(BN_1ETH),
        "contract balance mismatch"
      );
      const balance2b = toBN(await getBalance(ALICE));
      const gasUsed2b = toBN(result.receipt.gasUsed);
      const transact2b = await web3.eth.getTransaction(result.tx);
      const gasPrice2b = toBN(transact2b.gasPrice);
      assert.isTrue(
        balance2a.sub(balance2b.add(gasUsed2b.mul(gasPrice2b))).eq(BN_1ETH),
        "sender balance mismatch"
      );
      const info = await REMITTANCE.remittances(id);
      assert.strictEqual(info.sender, ALICE, "sender mismatch");
      assert.strictEqual(info.recipient, BOB, "recipient mismatch");
      assert.isTrue(BN_1ETH.sub(BN_FEE).eq(info.amount), "amount mismatch");
      // Won't check deadline. See comments above.
    });
  });

  describe("Function: receive", () => {
    it("should revert on remittance not set", async () => {
      await reverts(
        REMITTANCE.receive(ALICE, FAKE_ID, { from: BOB }),
        "remittance not set"
      );
    });

    it("should revert on remittance already claimed", async () => {
      const secret = new Array();
      uuidv4(null, secret, 0);
      const id = await REMITTANCE.generateRemittanceId(
        REMITTANCE.address,
        ALICE,
        BOB,
        secret
      );
      await REMITTANCE.transfer(id, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_1ETH
      });
      await REMITTANCE.receive(ALICE, secret, { from: BOB });
      await reverts(
        REMITTANCE.receive(ALICE, secret, { from: BOB }),
        "remittance already claimed"
      );
    });

    it("should revert on remittance not found", async () => {
      const secret = new Array();
      uuidv4(null, secret, 0);
      const id = await REMITTANCE.generateRemittanceId(
        REMITTANCE.address,
        ALICE,
        BOB,
        secret
      );
      await REMITTANCE.transfer(id, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_1ETH
      });
      await reverts(
        REMITTANCE.receive(ALICE, FAKE_ID, { from: BOB }),
        "remittance not set"
      );
    });

    it("should complete remittance (receive)", async () => {
      const secret = new Array();
      uuidv4(null, secret, 0);
      const id = await REMITTANCE.generateRemittanceId(
        REMITTANCE.address,
        ALICE,
        BOB,
        secret
      );
      await REMITTANCE.transfer(id, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_1ETH
      });
      const balance1a = toBN(await getBalance(REMITTANCE.address));
      const balance2a = toBN(await getBalance(BOB));
      const result = await REMITTANCE.receive(ALICE, secret, { from: BOB });
      await eventEmitted(result, "RemittanceReceived", log => {
        return (
          log.remittanceId === id &&
          log.recipient === BOB &&
          BN_1ETH.sub(BN_FEE).eq(log.amount)
        );
      });
      const balance1b = toBN(await getBalance(REMITTANCE.address));
      assert.isTrue(
        balance1a.sub(balance1b).eq(BN_1ETH.sub(BN_FEE)),
        "contract balance mismatch"
      );
      const balance2b = toBN(await getBalance(BOB));
      const gasUsed2b = toBN(result.receipt.gasUsed);
      const transact2b = await web3.eth.getTransaction(result.tx);
      const gasPrice2b = toBN(transact2b.gasPrice);
      assert.isTrue(
        balance2b
          .add(gasUsed2b.mul(gasPrice2b))
          .sub(balance2a)
          .eq(BN_1ETH.sub(BN_FEE)),
        "recipient balance mismatch"
      );
      const info = await REMITTANCE.remittances(id);
      assert.strictEqual(info.sender, ZEROx0, "sender not released");
      assert.strictEqual(info.recipient, ZEROx0, "recipient not released");
      assert.isTrue(info.amount.eq(BN_0), "amount not released");
      assert.isFalse(info.deadline.eq(BN_0), "deadline was released");
    });
  });

  describe("Function: reclaim", () => {
    it("should revert on remittance not set", async () => {
      await reverts(
        REMITTANCE.reclaim(BOB, FAKE_ID, { from: ALICE }),
        "remittance not set"
      );
    });

    it("should revert on remittance already claimed", async () => {
      const secret = new Array();
      uuidv4(null, secret, 0);
      const id = await REMITTANCE.generateRemittanceId(
        REMITTANCE.address,
        ALICE,
        BOB,
        secret
      );
      await REMITTANCE.transfer(id, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_1ETH
      });
      await REMITTANCE.receive(ALICE, secret, { from: BOB });
      await reverts(
        REMITTANCE.reclaim(BOB, secret, { from: ALICE }),
        "remittance already claimed"
      );
    });

    it("should revert on remittance not found", async () => {
      const secret = new Array();
      uuidv4(null, secret, 0);
      const id = await REMITTANCE.generateRemittanceId(
        REMITTANCE.address,
        ALICE,
        BOB,
        secret
      );
      await REMITTANCE.transfer(id, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_1ETH
      });
      await reverts(
        REMITTANCE.reclaim(BOB, FAKE_ID, { from: ALICE }),
        "remittance not set"
      );
    });

    it("should revert on too early to reclaim", async () => {
      const secret = new Array();
      uuidv4(null, secret, 0);
      const id = await REMITTANCE.generateRemittanceId(
        REMITTANCE.address,
        ALICE,
        BOB,
        secret
      );
      await REMITTANCE.transfer(id, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_1ETH
      });
      await reverts(
        REMITTANCE.reclaim(BOB, secret, { from: ALICE }),
        "too early to reclaim"
      );
    });

    it("should complete remittance (reclaim)", async () => {
      const secret = new Array();
      uuidv4(null, secret, 0);
      const id = await REMITTANCE.generateRemittanceId(
        REMITTANCE.address,
        ALICE,
        BOB,
        secret
      );
      await REMITTANCE.transfer(id, BOB, BN_DEADLINE, {
        from: ALICE,
        value: BN_1ETH
      });
      const balance1a = toBN(await getBalance(REMITTANCE.address));
      const balance2a = toBN(await getBalance(ALICE));
      await advanceTime(DEADLINE_MS);
      const result = await REMITTANCE.reclaim(BOB, secret, { from: ALICE });
      await eventEmitted(result, "RemittanceReclaimed", log => {
        return (
          log.remittanceId === id &&
          log.sender === ALICE &&
          BN_1ETH.sub(BN_FEE).eq(log.amount)
        );
      });
      const balance1b = toBN(await getBalance(REMITTANCE.address));
      assert.isTrue(
        balance1a.sub(balance1b).eq(BN_1ETH.sub(BN_FEE)),
        "contract balance mismatch"
      );
      const balance2b = toBN(await getBalance(ALICE));
      const gasUsed2b = toBN(result.receipt.gasUsed);
      const transact2b = await web3.eth.getTransaction(result.tx);
      const gasPrice2b = toBN(transact2b.gasPrice);
      assert.isTrue(
        balance2b
          .add(gasUsed2b.mul(gasPrice2b))
          .sub(balance2a)
          .eq(BN_1ETH.sub(BN_FEE)),
        "recipient balance mismatch"
      );
      const info = await REMITTANCE.remittances(id);
      assert.strictEqual(info.sender, ZEROx0, "sender not released");
      assert.strictEqual(info.recipient, ZEROx0, "recipient not released");
      assert.isTrue(info.amount.eq(BN_0), "amount not released");
      assert.isFalse(info.deadline.eq(BN_0), "deadline was released");
    });
  });
});
