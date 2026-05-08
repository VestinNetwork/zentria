export const launchpadAbi = [
  {
    type: "function",
    name: "launch",
    stateMutability: "payable",
    inputs: [
      {
        name: "p",
        type: "tuple",
        components: [
          {name: "name", type: "string"},
          {name: "symbol", type: "string"},
          {name: "totalSupply", type: "uint256"},
          {name: "buyTaxBps", type: "uint16"},
          {name: "sellTaxBps", type: "uint16"},
          {name: "maxWalletBps", type: "uint16"},
          {name: "maxTxBps", type: "uint16"},
          {name: "devAllocationBps", type: "uint16"},
          {name: "lockDuration", type: "uint256"},
        ],
      },
    ],
    outputs: [{name: "token", type: "address"}],
  },
  {
    type: "function",
    name: "totalLaunches",
    stateMutability: "view",
    inputs: [],
    outputs: [{type: "uint256"}],
  },
  {
    type: "function",
    name: "getLaunch",
    stateMutability: "view",
    inputs: [{name: "launchId", type: "uint256"}],
    outputs: [
      {
        type: "tuple",
        components: [
          {name: "token", type: "address"},
          {name: "pair", type: "address"},
          {name: "dev", type: "address"},
          {name: "lockId", type: "uint256"},
          {name: "vestingId", type: "uint256"},
          {name: "createdAt", type: "uint256"},
        ],
      },
    ],
  },
  {
    type: "function",
    name: "getLaunchByToken",
    stateMutability: "view",
    inputs: [{name: "token", type: "address"}],
    outputs: [
      {
        type: "tuple",
        components: [
          {name: "token", type: "address"},
          {name: "pair", type: "address"},
          {name: "dev", type: "address"},
          {name: "lockId", type: "uint256"},
          {name: "vestingId", type: "uint256"},
          {name: "createdAt", type: "uint256"},
        ],
      },
    ],
  },
  {
    type: "function",
    name: "treasury",
    stateMutability: "view",
    inputs: [],
    outputs: [{type: "address"}],
  },
  {
    type: "event",
    name: "TokenLaunched",
    inputs: [
      {name: "launchId", type: "uint256", indexed: true},
      {name: "token", type: "address", indexed: true},
      {name: "dev", type: "address", indexed: true},
      {name: "pair", type: "address", indexed: false},
      {name: "lockId", type: "uint256", indexed: false},
      {name: "vestingId", type: "uint256", indexed: false},
      {name: "ethLiquidity", type: "uint256", indexed: false},
      {name: "platformFee", type: "uint256", indexed: false},
    ],
  },
] as const;
