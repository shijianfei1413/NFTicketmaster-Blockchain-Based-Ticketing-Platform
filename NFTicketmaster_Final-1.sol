// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Importing the ERC721 standard and IERC721Receiver interface from OpenZeppelin
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

// NFTicketmaster contract definition, inheriting ERC721 and implementing IERC721Receiver
contract NFTicketmaster is ERC721, IERC721Receiver {
    // State variables
    address public owner; // Owner of the contract
    uint256 public totalOccasions; // Counter for total number of occasions created
    uint256 public totalSupply; // Counter for total number of NFT tickets issued
    uint256 public totalExtraFees; // State variable to track extra fees collected

    // Struct to define properties of an Occasion
    struct Occasion {
        uint256 id; //Event ID
        string name;
        uint256 cost;
        uint256 tickets;
        uint256 maxTickets;
        string date;
        string time;
        string location;
    }

    // Mappings for storing occasions and ticket information
    mapping(uint256 => Occasion) occasions;
    mapping(uint256 => mapping(address => bool)) public hasBought;
    mapping(uint256 => mapping(uint256 => address)) public seatTaken;
    mapping(uint256 => uint256[]) seatsTaken;

    // Modifier to restrict certain functions to only the owner of the contract
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    // Constructor to initialize the contract with a name and symbol for the NFT
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) {
        owner = msg.sender; // Setting the contract deployer as the owner
    }

    // Function to list a new occasion/event
    function list(
        string memory _name,
        uint256 _cost,
        uint256 _maxTickets,
        string memory _date,
        string memory _time,
        string memory _location
    ) public onlyOwner {
        totalOccasions++;  // Every time add 1 when run this function, 
        occasions[totalOccasions] = Occasion(totalOccasions, _name, _cost, 0, _maxTickets, _date, _time, _location); //wrote occasion to the blockchain/pass the id to the newly create event
    }

    // Function to mint a ticket for a specific occasion
    function mint(uint256 _id, uint256 _seat) public payable {
        // Validations for ticket minting
        require(_id != 0 && _id <= totalOccasions, "Invalid occasion ID"); //check that '_id' is not 0 and does not exceed the 'totalOccasions' count
        require(msg.value >= occasions[_id].cost, "Insufficient payment"); //ensures the user pays enough to mint the ticket
        require(seatTaken[_id][_seat] == address(0) && _seat <= occasions[_id].maxTickets, "Seat already taken or invalid"); //ensures the seat is not already taken (seatTaken[_id][_seat] == address(0)) and that the seat number is within the maximum ticket limit for the occasion (_seat <= occasions[_id].maxTickets).

        // Minting logic
        occasions[_id].tickets -= 1; // <- update ticket count
        hasBought[_id][msg.sender] = true; // <- update buying status - Marks that the sender (msg.sender) has bought a ticket for this occasion.
        seatTaken[_id][_seat] = msg.sender; // <- Assign seat - Records that the specific seat for the occasion is now taken by the sender.
        seatsTaken[_id].push(_seat); // <- updata seat currently taken - Adds the seat number to the list of taken seats for the occasion.
        totalSupply++;
        _safeMint(msg.sender, totalSupply);
    }

    // Function to get details of an occasion
    function getOccasion(uint256 _id) public view returns (Occasion memory) {
        return occasions[_id];
    }

    // Function to get a list of taken seats for an occasion
    function getSeatsTaken(uint256 _id) public view returns (uint256[] memory) {
        return seatsTaken[_id];
    }

    // Function for the owner to withdraw funds from ticket sales
    function withdraw() public onlyOwner {
        (bool success, ) = owner.call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    // Events for listing, purchasing, revoking, and updating tickets
    event List(address indexed seller, uint256 indexed tokenid, uint256 price);
    event Purchase(address indexed buyer, uint256 indexed tokenid, uint256 price);
    event Revoke(address indexed seller, uint256 indexed tokenid);
    event Update(address indexed seller, uint256 indexed tokenid, uint256 newPrice);

    // Struct to define a ticket order
    struct Order {
        address owner;
        uint256 price;
    }

    // Mapping to store information about ticket listings
    mapping(uint256 => Order) public nftList;

// Function to list a ticket for sale with extra fee calculation
function ticketlist(uint256 _tokenid, uint256 _price) public payable {
    // Validations for listing a ticket
    require(_price > 0, "Price must be greater than zero");
    require(ownerOf(_tokenid) == msg.sender, "Caller is not the ticket owner");
    require(getApproved(_tokenid) == address(this), "Contract not approved to sell this ticket");

    // Calculate the extra fee based on the listing price
    uint256 originalCost = occasions[_tokenid].cost;
    uint256 feePercentage = 0;
    uint256 priceDifferencePercentage = (_price * 100) / originalCost - 100;

    if (priceDifferencePercentage >= 100) {
        feePercentage = 30; // 30% for 100% or more increase
    } else if (priceDifferencePercentage >= 50) {
        feePercentage = 10; // 10% for 50% or more increase
    } else if (priceDifferencePercentage >= 20) {
        feePercentage = 5; // 5% for 20% or more increase
    }

    uint256 extraFee = (originalCost * feePercentage) / 100;

    // Require that enough Ether is sent to cover the extra fee
    require(msg.value >= extraFee, "Not enough Ether sent to cover the extra fee");

    // Add the extra fee to the totalExtraFees
    totalExtraFees += extraFee;

    // Listing logic
    nftList[_tokenid] = Order(msg.sender, _price);

    // Transfer the ticket to the contract
    safeTransferFrom(msg.sender, address(this), _tokenid);

    // Emit the List event
    emit List(msg.sender, _tokenid, _price);
    }


    // Function to purchase a listed ticket
    function ticketpurchase(uint256 _tokenid) public payable {
        // Validations for purchasing a ticket
        Order storage _order = nftList[_tokenid];
        require(_order.price > 0, "Invalid Price");
        require(msg.value >= _order.price, "Not enough ETH sent");
        require(ownerOf(_tokenid) == address(this), "Ticket not listed for sale");

        // Purchase logic
        _safeTransfer(address(this), msg.sender, _tokenid, "");
        payable(_order.owner).transfer(_order.price);
        if (msg.value > _order.price) {
            payable(msg.sender).transfer(msg.value - _order.price);
        }
        delete nftList[_tokenid];
        emit Purchase(msg.sender, _tokenid, _order.price);
    }

    // Function to cancel a ticket listing
    function revoke(uint256 _tokenid) public {
        // Validations for revoking a listing
        Order storage _order = nftList[_tokenid];
        require(_order.owner == msg.sender, "Not the ticket owner");
        require(ownerOf(_tokenid) == address(this), "Ticket not listed for sale");

        // Revoking logic
        _safeTransfer(address(this), msg.sender, _tokenid, "");
        delete nftList[_tokenid];
        emit Revoke(msg.sender, _tokenid);
    }

    // Function to update the price of a listed ticket
    function updateListingPrice(uint256 _tokenid, uint256 _newPrice) public {
        // Validations for updating a ticket's price
        Order storage _order = nftList[_tokenid];
        require(_newPrice > 0, "Invalid Price");
        require(_order.owner == msg.sender, "Not the ticket owner");
        require(ownerOf(_tokenid) == address(this), "Ticket not listed for sale");

        // Update price logic
        _order.price = _newPrice;
        emit Update(msg.sender, _tokenid, _newPrice);
    }

    // Function for the owner to withdraw collected extra fees
    function withdrawExtraFees() public onlyOwner {
        require(totalExtraFees > 0, "No extra fees to withdraw");

        uint256 amount = totalExtraFees;
        totalExtraFees = 0;

        (bool success, ) = owner.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    // Function to handle ERC721 token receipts
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
