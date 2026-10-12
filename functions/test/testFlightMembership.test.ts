import assert from "node:assert/strict";
import {describe, it} from "node:test";
import {verifyCurrentLifetimeMembership} from "../src/testFlightMembershipPolicy.js";
import {lifetimeProductId, monthlyProductId} from "../src/entitlementPolicy.js";
import {shouldApplyTransaction} from "../src/transactionUpdatePolicy.js";

describe("ongoing TestFlight membership", () => {
  const lifetime = {environment: "Production", productId: lifetimeProductId, active: true, expiresAt: null};

  it("detects a refund even when no notification has arrived", async () => {
    let stored = {...lifetime};
    let checks = 0;
    const result = await verifyCurrentLifetimeMembership(async () => [stored], async () => {
      checks++;
      stored = {...stored, active: false};
    });
    assert.equal(result, false);
    assert.equal(checks, 1);
  });

  it("does not use cached lifetime access when Apple is unreachable", async () => {
    await assert.rejects(verifyCurrentLifetimeMembership(async () => [lifetime], async () => {
      throw new Error("Apple unavailable");
    }), /Apple unavailable/);
  });

  it("rejects sandbox lifetime, monthly-only and missing purchases", async () => {
    for (const bindings of [[], [{...lifetime, environment: "Sandbox"}], [{...lifetime, productId: monthlyProductId}]]) {
      assert.equal(await verifyCurrentLifetimeMembership(async () => bindings, async () => {
        assert.fail("Non-lifetime production transaction must not be queried");
      }), false);
    }
  });

  it("allows a current lifetime purchase and rechecks after persistence", async () => {
    let reads = 0;
    let verified = false;
    assert.equal(await verifyCurrentLifetimeMembership(async () => {
      reads++;
      return [lifetime];
    }, async () => { verified = true; }), true);
    assert.equal(reads, 2);
    assert.equal(verified, true);
  });

  it("does not restore access from an old client transaction or out-of-order notification", () => {
    const refund = {signedDate: 200, revocationDate: 190};
    assert.equal(shouldApplyTransaction(refund, {signedDate: 100, revocationDate: null}), false);
    assert.equal(shouldApplyTransaction(refund, {signedDate: 200, revocationDate: null}), false);
    assert.equal(shouldApplyTransaction(refund, {revocationDate: null}), false);
    assert.equal(shouldApplyTransaction({revocationDate: 190}, {signedDate: 100, revocationDate: null}), false);
    assert.equal(shouldApplyTransaction({signedDate: 100}, refund), true);
    // A newer Apple refund reversal is legitimate; do not permanently blacklist.
    assert.equal(shouldApplyTransaction(refund, {signedDate: 300, revocationDate: null}), true);
  });

  it("does not let a freshly signed old subscription period overwrite a newer renewal", () => {
    const renewal = {purchaseDate: {toMillis: () => 200}, signedDate: 210};
    const oldPeriod = {purchaseDate: {toMillis: () => 100}, signedDate: 300};
    assert.equal(shouldApplyTransaction(renewal, oldPeriod), false);
    assert.equal(shouldApplyTransaction(oldPeriod, renewal), true);
    assert.equal(shouldApplyTransaction({...renewal, signedDate: undefined}, oldPeriod, true), false);
    assert.equal(shouldApplyTransaction({revocationDate: 190}, {signedDate: 300, revocationDate: null}, true), true);
  });
});
