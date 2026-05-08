export const devVestingAbi = [
  {
    type: "function",
    name: "getSchedule",
    stateMutability: "view",
    inputs: [{name: "scheduleId", type: "uint256"}],
    outputs: [
      {
        type: "tuple",
        components: [
          {name: "token", type: "address"},
          {name: "beneficiary", type: "address"},
          {name: "totalAmount", type: "uint256"},
          {name: "released", type: "uint256"},
          {name: "startAt", type: "uint64"},
        ],
      },
    ],
  },
  {
    type: "function",
    name: "releasable",
    stateMutability: "view",
    inputs: [{name: "scheduleId", type: "uint256"}],
    outputs: [{type: "uint256"}],
  },
  {
    type: "function",
    name: "release",
    stateMutability: "nonpayable",
    inputs: [{name: "scheduleId", type: "uint256"}],
    outputs: [],
  },
] as const;
