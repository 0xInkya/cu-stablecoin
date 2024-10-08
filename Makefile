-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil zktest

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :
	- forge install foundry-rs/forge-std@v1.5.3 --no-commit
	- forge install cyfrin/foundry-devops@0.1.0 --no-commit
	- forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit
	- forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1


#/*//////////////////////////////////////////////////////////////
#                          DEPLOYEMENT
#//////////////////////////////////////////////////////////////*/

# Deploy to Anvil
## make anvil
## make deploy
deploy:
	@forge script script/<SCRIPT_NAME>.s.sol:<CONTRACT_NAME> $(NETWORK_ARGS)

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

# Deploy to Sepolia
## make deploy ARGS="--network sepolia"
ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --account $(ACCOUNT) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif


#/*//////////////////////////////////////////////////////////////
#                          INTERACTIONS
#//////////////////////////////////////////////////////////////*/

# Address of the function caller goes here. Just put in $(DEFAULT_ANVIL_KEY) or $(SEPOLIA_ADDRESS)
SENDER_ADDRESS := <SENDER_ADDRESS>

# Call function-name of last deployed contract
## Anvil: make function-name
## Sepolia: make function-name ARGS="--network sepolia"
function-name:
	@forge script script/Interactions.s.sol:<CONTRACT_NAME> --sender $(SENDER_ADDRESS) $(NETWORK_ARGS)
