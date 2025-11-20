import { network } from "hardhat";

/**
 * Test script to check available APIs
 */
async function main() {
    console.log("Checking Hardhat 3 API...\n");

    const connection = await network.connect();
    console.log("Connection keys:", Object.keys(connection));
    console.log("\nViem keys:", Object.keys(connection.viem || {}));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
