-include .env

build:
	forge build

test-report:
	forge test --gas-report

coverage:
	forge coverage

deploy:
	forge script script/RoomieScript.s.sol:RoomieScript --rpc-url ${RPC_URL} --private-key ${PRIVATE_KEY} --broadcast
# deploy:
# 	forge script script/RoomieScript.s.sol:RoomieScript --rpc-url ${RPC_URL} --private-key ${PRIVATE_KEY} --broadcast --etherscan-api-key ${ETHERSCAN_API_KEY} --verify	