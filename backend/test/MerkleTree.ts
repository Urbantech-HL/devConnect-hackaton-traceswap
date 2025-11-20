import { keccak256, encodePacked, type Hex } from "viem";

export const createMerkleTree = (addresses: string[]): MerkleTree => {
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

export const getMerkleRoot = (tree: MerkleTree): Hex => {
  if (tree.layers.length === 0 || tree.layers[0].length === 0) return "0x";
  return tree.layers[tree.layers.length - 1][0];
};

export const getMerkleProof = (tree: MerkleTree, address: string): Hex[] => {
  const leaf = hashLeaf(address);
  let index = tree.leaves.indexOf(leaf);
  if (index === -1) {
    throw new Error("Leaf not found");
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

type MerkleTree = {
  leaves: Hex[];
  layers: Hex[][];
};

function hashLeaf(address: string): Hex {
  return keccak256(encodePacked(["address"], [address as Hex]));
}

function hashPair(a: Hex, b: Hex): Hex {
  return a < b
    ? keccak256(encodePacked(["bytes32", "bytes32"], [a, b]))
    : keccak256(encodePacked(["bytes32", "bytes32"], [b, a]));
}
