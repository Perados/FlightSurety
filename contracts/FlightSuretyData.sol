pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
     mapping(address => bool) private authorizedAppContracts;
     struct Airline {
        address _address;
        string name;
        bool isFunded;
        uint256 votes;
    }
    mapping(address => Airline) registeredAirlines;
    uint256  registeredAirlinesCounter = 0;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address _address;
    }
    mapping(bytes32 => Flight) private flights;

    struct Passenger{
        address passengerAddress;
        mapping (bytes32 => uint256) insuredFlights;
        uint256 credit;
    }
    mapping(address => Passenger) private passengers;
    address[] public passengerAddresses;

    uint256 totalFunds = 0;



    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor
                                (
                                ) 
                                public 
    {
        contractOwner = msg.sender;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational() 
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() 
                            public 
                            view 
                            returns(bool) 
    {
        return operational;
    }

    function authorizeCaller
                            (
                                address appContract
                            )
                            public
    {
        authorizedAppContracts[appContract] = true;
    }

    function isAirlineFunded(
        address airlineAddress
    ) external view requireIsOperational returns (bool) {
        return registeredAirlines[airlineAddress].isFunded;
    }

    function fundAirline
                            (
                                address airlineAddress,
                                uint256 amount
                            )
                            external
                            payable
                            requireIsOperational
    {

        registeredAirlines[airlineAddress].isFunded = true;
        totalFunds = totalFunds.add(amount);
    }




    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
    function setOperatingStatus
                            (
                                bool mode
                            ) 
                            external
                            requireContractOwner 
    {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function registerAirline
                            (   
                                string airlineName,
                                address airlineAddress
                            )
                            public
                            requireIsOperational
    {
       registeredAirlines[airlineAddress] = Airline({
           _address: airlineAddress,
           name: airlineName,
           isFunded: false,
           votes: 0
       });

       registeredAirlinesCounter = registeredAirlinesCounter.add(1);
    }

    function registerFlight(
        address airlineAddress,
        string flight,
        uint256 timestamp,
        uint8 status
    ) external requireIsOperational  {
        bytes32 key = getFlightKey(airlineAddress, flight, timestamp);
        require(!flights[key].isRegistered, "Flight was already registered");
        flights[key] = Flight({
            isRegistered: true,
            statusCode: status,
            updatedTimestamp: block.timestamp,
            _address: airlineAddress
        });
    }


   /**
    * @dev Buy insurance for a flight
    *
    */   
   function buy
                            (
                                bytes32 flightKey,
                                address passengerAddress,
                                uint256 insuredAmount
                            )
                            external
                            payable
                            requireIsOperational
    {
        if (passengers[passengerAddress].passengerAddress != address(0)) { 
            require(passengers[passengerAddress].insuredFlights[flightKey] == 0, "This flight is already insured");

        } else {
            passengers[passengerAddress] = Passenger({
                passengerAddress: passengerAddress,
                credit: 0
            });
            passengerAddresses.push(passengerAddress);
        }
        passengers[passengerAddress].insuredFlights[flightKey] = insuredAmount;
        totalFunds = totalFunds.add(insuredAmount);
    }


    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                (
                                    bytes32 flightKey
                                )
                                external
                                requireIsOperational
    {
        for (uint256 i = 0; i < passengerAddresses.length; i++) {
            if(passengers[passengerAddresses[i]].insuredFlights[flightKey] != 0) { // Insured flights
                uint256 payedPrice = passengers[passengerAddresses[i]].insuredFlights[flightKey];
                uint256 savedCredit = passengers[passengerAddresses[i]].credit;
                passengers[passengerAddresses[i]].insuredFlights[flightKey] = 0;
                passengers[passengerAddresses[i]].credit = savedCredit + payedPrice + payedPrice.div(2); // 1.5X the amount they paid
            }
        }
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (
                                address insuredPassenger
                            )
                            external
                            payable
                            requireIsOperational
    {
        require(insuredPassenger == tx.origin, "Contracts not allowed");
        require(passengers[insuredPassenger].passengerAddress != address(0), "The passenger is not insured");
        require(passengers[insuredPassenger].credit > 0, "There is not credit pending to be withdrawed for the passenger");
        uint256 credit = passengers[insuredPassenger].credit;
        require(address(this).balance > credit, "The contract does not have enough funds to pay the credit");
        passengers[insuredPassenger].credit = 0;
        insuredPassenger.transfer(credit);
    }


   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
    function fund
                            (   
                            )
                            public
                            payable
    {
    }
    
    function isAirlineRegistered (
                            address airlineAddress
                        )
                        external
                        view
                        returns (bool) {
        if (registeredAirlines[airlineAddress]._address == airlineAddress) {
            return true;
        } else {
            return false;
        }
    }

    function isFlightRegistered (
                            bytes32 flightKey
                        )
                        external
                        view
                        returns (bool) {
        if (flights[flightKey]._address == address(0)) {
            return true;
        } else {
            return false;
        }
    }


    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() 
                            external 
                            payable 
    {
        fund();
    }


}

