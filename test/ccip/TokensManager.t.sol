// pragma solidity ^0.8.0;

// import { Test, console, Vm } from "forge-std/Test.sol";
// import { CCIPLocalSimulatorFork, Register } from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
// import { IRouterClient, BurnMintERC677Helper, WETH9, LinkToken } from "@chainlink-local/src/ccip/CCIPLocalSimulator.sol";
// import { TokensManager, BurnMintERC677 } from "@contracts/TokensManager.sol";
// import { BurnMintTokensPool, ConcentratedTokensPool } from "@contracts/pool/BurnMintTokensPool.sol";
// import { RateLimiter } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/RateLimiter.sol";
// import { Client } from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
// import { IRouterClient } from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";

// contract TokensManagerTest is Test {
//   CCIPLocalSimulatorFork internal _ccipLocalSimulatorRoninTestnet;
//   CCIPLocalSimulatorFork internal _ccipLocalSimulatorSepolia;
//   TokensManager internal _tokensManagerRoninTestnet;
//   TokensManager internal _tokensManagerSepolia;
//   string public RONIN_TESTNET_RPC_URL = vm.rpcUrl("ronin-testnet");
//   string public SEPOLIA_RPC_URL = vm.rpcUrl("sepolia");
//   uint256 internal _roninTestnetForkId;
//   uint256 internal _sepoliaForkId;
//   Register.NetworkDetails internal _roninTestnetNetworkDetails;
//   Register.NetworkDetails internal _sepoliaNetworkDetails;
//   address internal _admin = makeAddr("admin");
//   BurnMintTokensPool internal _concentratedTokensPoolRoninTestnet;
//   BurnMintTokensPool internal _concentratedTokensPoolSepolia;
//   string internal _name = "Test Token";
//   address internal _deployer = makeAddr("deployer");
//   string internal _symbol = "TEST";
//   uint8 internal _decimals = 18;
//   uint256 internal _sepoliaChainId = 11155111;
//   uint256 internal _roninTestnetChainId = 2021;
//   address internal _BnMTokenRoninTestnet;
//   address internal _BnMTokenSepolia;

//   modifier executeOnFork(
//     uint256 forkId
//   ) {
//     vm.selectFork(forkId);
//     _;
//   }

//   function setUp() public {
//     _roninTestnetNetworkDetails = Register.NetworkDetails({
//       chainSelector: 13116810400804392105,
//       routerAddress: 0x0aCAe4e51D3DA12Dd3F45A66e8b660f740e6b820,
//       linkAddress: 0x5bB50A6888ee6a67E22afFDFD9513be7740F1c15,
//       wrappedNativeAddress: 0xA959726154953bAe111746E265E6d754F48570E6,
//       ccipBnMAddress: 0xA8C0c11bf64AF62CDCA6f93D3769B88BdD7cb93D,
//       ccipLnMAddress: 0x139E99f0ab4084E14e6bb7DacA289a91a2d92927,
//       rmnProxyAddress: 0xf206c6D3f3810eBbD75e7B4684291b5e51023D2f,
//       registryModuleOwnerCustomAddress: 0xE31827cd24d7D419fC17E7Ff889BaF62A17991A0,
//       tokenAdminRegistryAddress: 0x057879f376041D527a98327DE2Ec00F201c9cA25
//     });
//     _roninTestnetForkId = vm.createSelectFork(RONIN_TESTNET_RPC_URL);
//     _sepoliaForkId = vm.createFork(SEPOLIA_RPC_URL);
//     _setUpRoninTestnet();
//     _setUpSepolia();
//     _setChainSelector();
//     _applyChainUpdates(_roninTestnetForkId);
//     _applyChainUpdates(_sepoliaForkId);
//     _BnMTokenRoninTestnet = _createTokenUnderManagement(_roninTestnetForkId);
//     _ccipLocalSimulatorRoninTestnet.switchChainAndRouteMessage(_sepoliaForkId);
//     _BnMTokenSepolia = _BnMTokenRoninTestnet;
//     vm.label(_BnMTokenSepolia, "BnM Token Sepolia");
//     vm.label(_BnMTokenRoninTestnet, "BnM Token Ronin Testnet");
//   }

//   function _setUpSepolia() internal executeOnFork(_sepoliaForkId) {
//     _ccipLocalSimulatorSepolia = new CCIPLocalSimulatorFork();
//     _sepoliaNetworkDetails = _ccipLocalSimulatorSepolia.getNetworkDetails(_sepoliaChainId);

//     vm.startBroadcast(_deployer);
//     vm.setNonce(_deployer, 100);
//     _tokensManagerSepolia = new TokensManager(_sepoliaNetworkDetails.routerAddress);
//     console.log("Tokens manager address on sepolia:", address(_tokensManagerSepolia));

//     //deploy pool on sepolia
//     _concentratedTokensPoolSepolia = new BurnMintTokensPool(
//       new address[](0), new address[](0), _sepoliaNetworkDetails.rmnProxyAddress, _sepoliaNetworkDetails.routerAddress
//     );
//     _concentratedTokensPoolSepolia.setTokensManager(address(_tokensManagerSepolia));
//     _tokensManagerSepolia.initialize(
//       _admin,
//       _sepoliaNetworkDetails.tokenAdminRegistryAddress,
//       address(_concentratedTokensPoolSepolia),
//       _sepoliaNetworkDetails.registryModuleOwnerCustomAddress
//     );
//     _ccipLocalSimulatorSepolia.setNetworkDetails(_roninTestnetChainId, _roninTestnetNetworkDetails);

//     vm.stopBroadcast();
//     vm.label(address(_concentratedTokensPoolSepolia), "Sepolia Concentrated Pool");
//     vm.label(address(_tokensManagerSepolia), "Sepolia Tokens Manager");
//   }

//   function _setUpRoninTestnet() internal executeOnFork(_roninTestnetForkId) {
//     _ccipLocalSimulatorRoninTestnet = new CCIPLocalSimulatorFork();

//     //deploy pool on ronin testnet
//     vm.startBroadcast(_deployer);
//     _concentratedTokensPoolRoninTestnet = new BurnMintTokensPool(
//       new address[](0),
//       new address[](0),
//       _roninTestnetNetworkDetails.rmnProxyAddress,
//       _roninTestnetNetworkDetails.routerAddress
//     );
//     _ccipLocalSimulatorRoninTestnet.setNetworkDetails(_roninTestnetChainId, _roninTestnetNetworkDetails);

//     vm.setNonce(_deployer, 100);
//     _tokensManagerRoninTestnet = new TokensManager(_roninTestnetNetworkDetails.routerAddress);
//     console.log("Tokens manager address on ronin testnet:", address(_tokensManagerRoninTestnet));
//     _tokensManagerRoninTestnet.initialize(
//       _admin,
//       _roninTestnetNetworkDetails.tokenAdminRegistryAddress,
//       address(_concentratedTokensPoolRoninTestnet),
//       _roninTestnetNetworkDetails.registryModuleOwnerCustomAddress
//     );
//     _concentratedTokensPoolRoninTestnet.setTokensManager(address(_tokensManagerRoninTestnet));

//     vm.stopBroadcast();
//     vm.label(address(_concentratedTokensPoolRoninTestnet), "Ronin Testnet Concentrated Pool");
//     vm.label(address(_tokensManagerRoninTestnet), "Ronin Testnet Tokens Manager");
//   }

//   function _createTokenUnderManagement(
//     uint256 forkId
//   ) internal executeOnFork(forkId) returns (address) {
//     if (forkId == _roninTestnetForkId) {
//       return _tokensManagerRoninTestnet.createTokenUnderManagement(_name, _symbol, _decimals, 0, 10_000 ether);
//     } else if (forkId == _sepoliaForkId) {
//       return _tokensManagerSepolia.createTokenUnderManagement(_name, _symbol, _decimals, 0, 10_000 ether);
//     }
//   }

//   function _setChainSelector() internal {
//     vm.startPrank(_admin);
//     vm.selectFork(_roninTestnetForkId);
//     vm.deal(address(_tokensManagerRoninTestnet), 10000 ether);
//     _tokensManagerRoninTestnet.setDestinationChainSelector(_sepoliaNetworkDetails.chainSelector);
//     _tokensManagerRoninTestnet.setRemoteTokensManager(address(_tokensManagerSepolia));
//     vm.selectFork(_sepoliaForkId);
//     vm.deal(address(_tokensManagerSepolia), 10000 ether);
//     _tokensManagerSepolia.setDestinationChainSelector(_roninTestnetNetworkDetails.chainSelector);
//     _tokensManagerSepolia.setRemoteTokensManager(address(_tokensManagerRoninTestnet));
//     vm.stopPrank();
//   }

//   function testConcrete_DeployTokensManagers_HaveTheSameAddress_OnBothChains() public {
//     assertEq(address(_tokensManagerRoninTestnet), address(_tokensManagerSepolia));
//   }

//   function testConcrete_CreateTokenUnderManagement_HasTheSameAddress_OnRoninTestnet() public {
//     address tokenRoninTestnet = _createTokenUnderManagement(_roninTestnetForkId);
//     _ccipLocalSimulatorRoninTestnet.switchChainAndRouteMessage(_sepoliaForkId);
//     assertTrue(_tokensManagerSepolia.isTokenUnderManagement(tokenRoninTestnet));
//   }

//   function testConcrete_CreateTokenUnderManagement_HasTheSameAddress_OnSepolia() public {
//     address tokenSepolia = _createTokenUnderManagement(_sepoliaForkId);
//     _ccipLocalSimulatorSepolia.switchChainAndRouteMessage(_roninTestnetForkId);
//     assertTrue(_tokensManagerRoninTestnet.isTokenUnderManagement(tokenSepolia));
//   }

//   function testConcrete_Transfer100Token_WithTheSameAddress_FromRoninTestnetToSepolia()
//     public
//     executeOnFork(_roninTestnetForkId)
//   {
//     Client.EVM2AnyMessage memory message = _buildCCIPMessage(address(this), _BnMTokenRoninTestnet, 100 ether);
//     IRouterClient router = IRouterClient(_tokensManagerRoninTestnet.getRouter());
//     uint256 fee = router.getFee(_sepoliaNetworkDetails.chainSelector, message);
//     BurnMintERC677(_BnMTokenRoninTestnet).approve(address(router), type(uint256).max);
//     uint256 balanceOnRonin = BurnMintERC677(_BnMTokenRoninTestnet).balanceOf(address(this));
//     vm.deal(address(this), fee);
//     router.ccipSend{ value: fee }(_sepoliaNetworkDetails.chainSelector, message);
//     _ccipLocalSimulatorRoninTestnet.switchChainAndRouteMessage(_sepoliaForkId);
//     uint256 balanceOnSepolia = BurnMintERC677(_BnMTokenSepolia).balanceOf(address(this));
//   }

//   function testConcrete_Transfer100Token_WithTheSameAddress_FromSepoliaToRoninTestnet()
//     public
//     executeOnFork(_sepoliaForkId)
//   {
//     Client.EVM2AnyMessage memory message = _buildCCIPMessage(address(this), _BnMTokenSepolia, 100 ether);
//     IRouterClient router = IRouterClient(_tokensManagerSepolia.getRouter());
//     uint256 fee = router.getFee(_roninTestnetNetworkDetails.chainSelector, message);
//     BurnMintERC677(_BnMTokenSepolia).approve(address(router), type(uint256).max);
//     vm.deal(address(this), fee);
//     router.ccipSend{ value: fee }(_roninTestnetNetworkDetails.chainSelector, message);
//     _ccipLocalSimulatorSepolia.switchChainAndRouteMessage(_roninTestnetForkId);
//   }

//   function _applyChainUpdates(
//     uint256 forkId
//   ) internal executeOnFork(forkId) {
//     ConcentratedTokensPool.ChainUpdate[] memory chainUpdates = new ConcentratedTokensPool.ChainUpdate[](1);
//     bytes[] memory remoteTokenAddresses = new bytes[](0);
//     address[] memory tokens = new address[](0);
//     bytes memory remotePoolAddress;

//     if (forkId == _roninTestnetForkId) {
//       remotePoolAddress = abi.encode(address(_concentratedTokensPoolSepolia));
//       chainUpdates[0] = ConcentratedTokensPool.ChainUpdate({
//         remoteChainSelector: _sepoliaNetworkDetails.chainSelector,
//         allowed: true,
//         remotePoolAddress: remotePoolAddress,
//         remoteTokenAddresses: remoteTokenAddresses,
//         tokens: tokens,
//         outboundRateLimiterConfig: RateLimiter.Config({ isEnabled: true, capacity: 10000 ether, rate: 100 ether }),
//         inboundRateLimiterConfig: RateLimiter.Config({ isEnabled: true, capacity: 10000 ether, rate: 100 ether })
//       });
//       vm.prank(_deployer);
//       _concentratedTokensPoolRoninTestnet.applyChainUpdates(chainUpdates);
//     } else {
//       remotePoolAddress = abi.encode(address(_concentratedTokensPoolRoninTestnet));
//       chainUpdates[0] = ConcentratedTokensPool.ChainUpdate({
//         remoteChainSelector: _roninTestnetNetworkDetails.chainSelector,
//         allowed: true,
//         remotePoolAddress: remotePoolAddress,
//         remoteTokenAddresses: remoteTokenAddresses,
//         tokens: tokens,
//         outboundRateLimiterConfig: RateLimiter.Config({ isEnabled: true, capacity: 10000 ether, rate: 100 ether }),
//         inboundRateLimiterConfig: RateLimiter.Config({ isEnabled: true, capacity: 10000 ether, rate: 100 ether })
//       });
//       vm.prank(_deployer);
//       _concentratedTokensPoolSepolia.applyChainUpdates(chainUpdates);
//     }
//   }

//   function _buildCCIPMessage(
//     address receiver,
//     address tokenAddress,
//     uint256 amount
//   ) internal view returns (Client.EVM2AnyMessage memory message) {
//     Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
//     tokenAmounts[0] = Client.EVMTokenAmount({ token: tokenAddress, amount: amount });
//     // Create a CCIP message to create the token on the destination chain
//     message = Client.EVM2AnyMessage({
//       receiver: abi.encode(receiver), // ABI-encoded receiver address
//       data: "", // ABI-encoded string
//       tokenAmounts: tokenAmounts, // No tokens to transfer
//       extraArgs: Client._argsToBytes(
//         // Additional arguments, setting gas limit
//         Client.EVMExtraArgsV2({
//           gasLimit: 100_000, // Gas limit for the callback on the destination chain
//           allowOutOfOrderExecution: true // Allows the message to be executed out of order relative to other messages from the same sender
//          })
//       ),
//       // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
//       feeToken: address(0)
//     });
//   }
// }
