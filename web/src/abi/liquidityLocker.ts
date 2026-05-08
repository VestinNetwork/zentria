export const liquidityLockerAbi = [
  {
    type: "function",
    name: "getLock",
    stateMutability: "view",
    inputs: [{name: "lockId", type: "uint256"}],
    outputs: [
      {
        type: "tuple",
        components: [
          {name: "token", type: "address"},
          {name: "owner", type: "address"},
          {name: "amount", type: "uint256"},
          {name: "unlockAt", type: "uint256"},
          {name: "withdrawn", type: "bool"},
        ],
      },
    ],
  },
  {
    type: "function",
    name: "withdraw",
    stateMutability: "nonpayable",
    inputs: [{name: "lockId", type: "uint256"}],
    outputs: [],
  },
] as const;
