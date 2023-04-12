// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./MerkleTreeWithHistory.sol";
import "./ReentrancyGuard.sol";

interface IVerifier {
    function verifyProof(bytes memory _proof, uint256[2] memory _input) external returns (bool);
}

contract Voting is MerkleTreeWithHistory, ReentrancyGuard {
    IVerifier public immutable verifier;
    
    struct Proposal {
        string question;
        string[] options;
        uint256[] counts;
        mapping(address => bool) claimed;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public nextProposalId;
    address public deployer;

    mapping(bytes32 => bool) public nullifierHashes;
    mapping(bytes32 => bool) public commitments;

    event ProposalCreated(uint256 proposalID, string question, string[] options);
    event BallotCreated(uint256 proposalID, bytes32 indexed commitment, uint32 leafIndex, uint256 timestamp);
    event Vote(uint256 proposalID, uint256 vote, bytes32 nullifierHash);

    constructor(
        IVerifier _verifier,
        IHasher _hasher,
        uint32 _merkleTreeHeight,
        address _deployer
    ) MerkleTreeWithHistory(_merkleTreeHeight, _hasher) {
        verifier = _verifier;
        nextProposalId = 1;
        deployer = _deployer;
    }

    function createProposal(string memory _question, string[] memory _options) external nonReentrant {
        require(msg.sender == deployer);

        uint256 proposalId = nextProposalId;
        nextProposalId += 1;

        uint256[] memory counts = new uint256[](_options.length);

        proposals[proposalId].question = _question;
        proposals[proposalId].options = _options;
        proposals[proposalId].counts = counts;

        emit ProposalCreated(proposalId, _question, _options);
    }

    function createBallot(uint256 _proposalID, bytes32 _commitment) external nonReentrant {
        require(!commitments[_commitment], "The commitment has been submitted");
        require(_proposalID <= getProposalCount(), "Not a valid proposal ID");
        require(!proposals[_proposalID].claimed[msg.sender], "Ballot already claimed for this proposal");

        uint32 insertedIndex = _insert(_commitment);
        commitments[_commitment] = true;
        proposals[_proposalID].claimed[msg.sender] = true;
        emit BallotCreated(_proposalID, _commitment, insertedIndex, block.timestamp);
    }

    function vote(
        uint256 _proposalID,
        uint256 _vote,
        bytes calldata _proof,
        bytes32 _root,
        bytes32 _nullifierHash
    ) external nonReentrant {
        require(_proposalID <= getProposalCount());
        require(_vote < proposals[_proposalID].options.length);
        require(!nullifierHashes[_nullifierHash], "The ballot has been already cast");
        require(isKnownRoot(_root), "Cannot find your merkle root");
        require(
            verifier.verifyProof(
                _proof,
                [uint256(_root), uint256(_nullifierHash)]
        ),
        "Invalid withdraw proof"
        );

        proposals[_proposalID].counts[_vote] += 1;
        nullifierHashes[_nullifierHash] = true;
        emit Vote(_proposalID, _vote, _nullifierHash);
    }

    function getProposalOptions(uint256 proposalId) external view returns (string[] memory) {
        return proposals[proposalId].options;
    }

    function getProposalCount() public view returns (uint256) {
        return nextProposalId - 1;
    }

    function checkClaimed(uint256 proposalId, address voter) external view returns (bool) {
        return proposals[proposalId].claimed[voter];
    }

    function getOptionCount(uint256 proposalId) external view returns (uint256) {
        return proposals[proposalId].options.length;
    }
}