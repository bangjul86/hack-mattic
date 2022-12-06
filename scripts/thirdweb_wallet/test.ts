import { ethers } from "ethers";
import { ThirdwebSDK } from "@thirdweb-dev/sdk";
import { readFileSync } from "fs";

import dotenv from "dotenv";
dotenv.config();

const CreateAccountParams = [
  { name: "signer", type: "address" },
  { name: "credentials", type: "bytes32" },
  { name: "deploymentSalt", type: "bytes32" },
  { name: "initialAccountBalance", type: "uint256" },
  { name: "validityStartTimestamp", type: "uint128" },
  { name: "validityEndTimestamp", type: "uint128" },
];

const TransactionParams = [
  { name: "target", type: "address" },
  { name: "data", type: "bytes" },
  { name: "nonce", type: "uint256" },
  { name: "value", type: "uint256" },
  { name: "gas", type: "uint256" },
  { name: "validityStartTimestamp", type: "uint128" },
  { name: "validityEndTimestamp", type: "uint128" },
];

const TransactionRequest = [
  { name: "signer", type: "address" },
  { name: "credentials", type: "bytes32" },
  { name: "value", type: "uint256" },
  { name: "gas", type: "uint256" },
  { name: "data", type: "bytes" },
  { name: "validityStartTimestamp", type: "uint128" },
  { name: "validityEndTimestamp", type: "uint128" },
];

async function main() {
  /*///////////////////////////////////////////////////////////////
                    Connect to WalletEntrypoint
    //////////////////////////////////////////////////////////////*/

  const WALLET_ADMIN: string = "0x879C0B8388591F542C509d58e3fa061040EB08b4";

  const sdk = ThirdwebSDK.fromPrivateKey(
    process.env.THIRDWEB_WALLET_TEST_PKEY as string,
    "optimism-goerli",
    {
      gasless: {
        openzeppelin: {
          relayerUrl: "https://api.defender.openzeppelin.com/autotasks/23a23d0f-886a-4858-a14d-ab08ed487c4a/runs/webhook/74b0e036-fd2e-418b-97d7-69ac094edf7b/8RTrzhrMW56WEcNYXd54Bg",
          relayerForwarderAddress: "0x5001A14CA6163143316a7C614e30e6041033Ac20"
        }
      }
    }
  );
  const entrypoint = await sdk.getContract(WALLET_ADMIN);

  /*///////////////////////////////////////////////////////////////
            Create an account / get an account for signer
    //////////////////////////////////////////////////////////////*/

  const username = "test_user";
  const password = "super_secret";

  const createParams = {
    signer: await sdk.wallet.getAddress(),
    credentials: ethers.utils.solidityKeccak256(["string", "string"], [username, password]),
    deploymentSalt: ethers.utils.formatBytes32String("randomSaltSalt"),
    initialAccountBalance: 0,
    validityStartTimestamp: 0,
    validityEndTimestamp: Math.floor(Date.now() / 1000) + 10_000,
  };

  const wrapper = (entrypoint as any).contractWrapper;
  const chainId = (await sdk.getProvider().getNetwork()).chainId;

  const signaturForCreateAccount = await wrapper.signTypedData(
    sdk.getSigner(),
    {
      name: "thirdwebWallet_Admin",
      version: "1",
      chainId,
      verifyingContract: WALLET_ADMIN,
    },
    { CreateAccountParams: CreateAccountParams },
    createParams,
  );

  console.log("\nSignature generated for account creation: ", signaturForCreateAccount);

  // UNCOMMENT TO CREATE NEW ACCOUNT
  // await entrypoint.call("createAccount", createParams, signaturForCreateAccount);

  const signerCredentialPair = ethers.utils.solidityKeccak256(
    ["bytes"],
    [ethers.utils.defaultAbiCoder.encode(["address", "bytes32"], [createParams.signer, createParams.credentials])],
  );
  const accountAddress: string = await entrypoint.call("accountOf", signerCredentialPair);

  console.log("Your account is: ", accountAddress);

  /*///////////////////////////////////////////////////////////////
                Perforfming a smart contract interaction
    //////////////////////////////////////////////////////////////*/

  const TOKEN_ADDRESS = "0x88aa7d12Abe7b64E843A3F9a12A57cD40BF68DD8";
  const tokenContract = await sdk.getContract(TOKEN_ADDRESS);

  const accountContract = await sdk.getContract(
    accountAddress,
    JSON.parse(readFileSync("artifacts_forge/Wallet.sol/Wallet.json", "utf-8")).abi,
  );
  const nonce = await accountContract.call("nonce");

  console.log("Account nonce: ", nonce);

  const gasForAccountTransaction = await tokenContract.estimator.gasLimitOf("mintTo", [
    accountAddress,
    ethers.utils.parseEther("1"),
  ]);

  console.log("Mint Gas Limit: ", gasForAccountTransaction.toString());

  const accountTransactionParams = {
    target: TOKEN_ADDRESS,
    data: tokenContract.encoder.encode("mintTo", [accountAddress, ethers.utils.parseEther("1")]),
    nonce: nonce,
    value: 0,
    gas: gasForAccountTransaction.add(50_000),
    validityStartTimestamp: 0,
    validityEndTimestamp: Math.floor(Date.now() / 1000) + 10_000,
  };

  console.log("Account transaction params: ", accountTransactionParams);

  const signaturForTransactionParams = await wrapper.signTypedData(
    sdk.getSigner(),
    {
      name: "thirdwebWallet",
      version: "1",
      chainId,
      verifyingContract: accountAddress,
    },
    { TransactionParams: TransactionParams },
    accountTransactionParams,
  );

  console.log("Signature for Wallet calling mintTo: ", signaturForTransactionParams);

  const accountTransactionData = accountContract.encoder.encode("execute", [
    accountTransactionParams,
    signaturForTransactionParams,
  ]);

  // NOTE: since the caller in callStatic is the SDK's connected signer and not the admin contract, the estimateGas method throws.
  // const gasForAdminTransaction = await accountContract.estimator.gasLimitOf("execute", [accountTransactionParams, signaturForTransactionParams]);

  const adminTransactionParams = {
    signer: createParams.signer,
    credentials: createParams.credentials,
    value: 0,
    gas: 200_000,
    data: accountTransactionData,
    validityStartTimestamp: 0,
    validityEndTimestamp: Math.floor(Date.now() / 1000) + 10_000,
  };

  const signaturForTransactionRequest = await wrapper.signTypedData(
    sdk.getSigner(),
    {
      name: "thirdwebWallet_Admin",
      version: "1",
      chainId,
      verifyingContract: WALLET_ADMIN,
    },
    { TransactionRequest: TransactionRequest },
    adminTransactionParams,
  );

  console.log("Signature for Wallet Admin calling execute: ", signaturForTransactionRequest);
  console.log("signaturForTransactionRequest", adminTransactionParams);

  entrypoint.interceptor.overrideNextTransaction(() => {
    return { gasLimit: 600_000 };
  });
  const tx = await entrypoint.call("execute", adminTransactionParams, signaturForTransactionRequest);

  console.log(tx);
}

main()
  .then(() => process.exit(0))
  .catch(err => {
    console.error(err);
    process.exit(1);
  });