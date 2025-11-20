import { keccak256, encodePacked, type Hex } from 'viem';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const whitelistPath = path.join(__dirname, 'whitelist.json');
const whitelistRaw = fs.readFileSync(whitelistPath, 'utf8');
const whitelist: {
    buyers: string[];
    suppliers: string[];
    admins: string[];
} = JSON.parse(whitelistRaw);

type MerkleTree = {
    leaves: Hex[];
    layers: Hex[][];
};

const hashLeaf = (address: string): Hex =>
    keccak256(encodePacked(['address'], [address as Hex]));

const hashPair = (a: Hex, b: Hex): Hex =>
    a < b
        ? keccak256(encodePacked(['bytes32', 'bytes32'], [a, b]))
        : keccak256(encodePacked(['bytes32', 'bytes32'], [b, a]));

const buildMerkleTree = (addresses: string[]): MerkleTree => {
    const leaves = addresses
        .map(hashLeaf)
        .sort((a, b) => (a.toLowerCase() < b.toLowerCase() ? -1 : 1));

    const layers: Hex[][] = [leaves];
    let currentLayer = leaves;

    while (currentLayer.length > 1) {
        const nextLayer: Hex[] = [];
        for (let i = 0; i < currentLayer.length; i += 2) {
            if (i + 1 < currentLayer.length) {
                nextLayer.push(hashPair(currentLayer[i], currentLayer[i + 1]));
            } else {
                nextLayer.push(hashPair(currentLayer[i], currentLayer[i]));
            }
        }
        layers.push(nextLayer);
        currentLayer = nextLayer;
    }

    return { leaves, layers };
};

const getMerkleRoot = (tree: MerkleTree): Hex => {
    if (tree.layers.length === 0 || tree.layers[0].length === 0) return '0x';
    return tree.layers[tree.layers.length - 1][0];
};

const getMerkleProof = (tree: MerkleTree, address: string): Hex[] => {
    const leaf = hashLeaf(address);
    let index = tree.leaves.indexOf(leaf);
    if (index === -1) {
        throw new Error('Leaf not found in Merkle tree');
    }

    const proof: Hex[] = [];
    for (let layerIndex = 0; layerIndex < tree.layers.length - 1; layerIndex++) {
        const layer = tree.layers[layerIndex];
        const isEven = index % 2 === 0;
        if (isEven) {
            if (index + 1 < layer.length) {
                proof.push(layer[index + 1]);
            } else {
                proof.push(layer[index]);
            }
        } else {
            proof.push(layer[index - 1]);
        }
        index = Math.floor(index / 2);
    }
    return proof;
};

const buildProofMap = (addresses: string[], tree: MerkleTree): Record<string, Hex[]> =>
    addresses.reduce<Record<string, Hex[]>>((acc, address) => {
        acc[address] = getMerkleProof(tree, address);
        return acc;
    }, {});

async function main() {
    console.log('Generating Merkle roots and proofs with viem...');

    const buyersTree = buildMerkleTree(whitelist.buyers);
    const suppliersTree = buildMerkleTree(whitelist.suppliers);
    const adminsTree = buildMerkleTree(whitelist.admins);

    const roots = {
        buyerMerkleRoot: getMerkleRoot(buyersTree),
        supplierMerkleRoot: getMerkleRoot(suppliersTree),
        adminMerkleRoot: getMerkleRoot(adminsTree),
    };

    const rootsPath = path.join(__dirname, 'merkle-roots.json');
    fs.writeFileSync(rootsPath, JSON.stringify(roots, null, 2));

    const buyerProofs = buildProofMap(whitelist.buyers, buyersTree);
    const supplierProofs = buildProofMap(whitelist.suppliers, suppliersTree);
    const adminProofs = buildProofMap(whitelist.admins, adminsTree);

    const buyerProofsPath = path.join(__dirname, 'buyer-proofs.json');
    const supplierProofsPath = path.join(__dirname, 'supplier-proofs.json');
    const adminProofsPath = path.join(__dirname, 'admin-proofs.json');

    fs.writeFileSync(buyerProofsPath, JSON.stringify(buyerProofs, null, 2));
    fs.writeFileSync(supplierProofsPath, JSON.stringify(supplierProofs, null, 2));
    fs.writeFileSync(adminProofsPath, JSON.stringify(adminProofs, null, 2));

    console.log('Roots written to', rootsPath);
    console.log('Buyer proofs written to', buyerProofsPath);
    console.log('Supplier proofs written to', supplierProofsPath);
    console.log('Admin proofs written to', adminProofsPath);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
