/*
 * 
 * private static variables:
 *     initialized- set true when initdata is called. Tells whether most of the other variables have been initalized.
 *     squares- a list containing every Game_Square__c record for the current game.
 *     squareMap- a map containing the same contents as "squares" but with the corresponding IDs as keys
 *         the purpose of this is so getting all the needed fields isn't a problem once you have the ID
 *     pieces- a list containing every Game_Piece__c record for the current game.
 *     pieceMap a map containing the same contents as "pieces" but with the corresponding IDs as keys
 *     history- the list of moves for the game, in order from most to least recent.
 *     alivepieces- a map with keys "White" and "Black", each matching to a list of uncaptured pieces of the corresponding color.
 *     game- the current Game__c object.
 *     setCastleRights- which castling rights have already been calculated.
 *         The order is white kingside, white queenside, black kingside, black queenside.
 *         If an index is false, the value in the corresponding index of castleRights is a meaningless placeholder- the true value must be calculated.
 *         This is to avoid calculating all values for castleRights if not necessary, without having to calculate them multiple times.
 *     castleRights- which castling rights still exist.
 *         The order is the same as with setCastleRights.
 *         The value in castleRights doesn't matter unless the corresponding value in setCastleRights is true.
 * 
 * The public static variables are possible return values for "isValidMove" and "validatePath".
 * 
 * functions:
 *     
 * Misc information:
 *     There is a global event called Chess_Piece_Move__e that frequently gets published.
 *     The event has one value: Squares__c
 *     Originally, it was just the changed squares- however, the event is much more versatile, and Squares__c can contain more information now.
 *     There are many possible values of Squares__c, but it must fit one of the following regular expressions:
 *         /P([a-h][18])/: A pawn was promoted on the square represented by the regex group.
 *         /M([a-h][1-8]){2,4}/: A move occurred. The squares represented by the regex group have changed. It will be 2 squares for most moves, 3 for en passant, 4 for castle.
 *         /O([WB])/: A player offered a draw. The regex group represents which player offered it*.
 *         /D([AS3I]|50)/: A draw occurred. The regex group represents what caused the draw.
 *             A: agreement
 *             S: stalemate
 *             3: 3 time repetition
 *             I: insufficient material for checkmate
 *             50: 50 move rule
 *         /W([WB])([CR])/: A player won. The first regex group represents which player won*. The second regex group represents how: 'C' for checkmate, 'R' for resignation.
 *      *If the explanation says ([WB]) represents which player, 'W' means white and 'B' means black.
 * 
 *      There are four directions that code or comments may refer to: towards white, towards black, queenside, kingside.
 *      This is preferred over the traditional forward/backward/left/right because it eliminates ambiguity of "from which player's perspective".
 *          It's sort of like using north/south/east/west.
 *      "towards white" means decreasing the row (rank) number- moving towards white's starting position.
 *      "towards black" means increasing the row (rank) number- moving towards black's starting position.
 *      "queenside" means decreasing the column (file) number- moving towards the side edge that the queens start closer to. Left for white, right for black.
 *      "kingside" means increasing the column (file) number- moving towards the side edge that the kings start closer to. Right for white, left for black.
 */ 
public class GameController {
	
    private static boolean initialized = false;
	private static List<Game_Square__c> squares = null;
    private static Map<ID,Game_Square__c> squareMap = null;
	private static List<Game_Piece__c> pieces = null;
    private static Map<ID,Game_Piece__c> pieceMap = null;
	private static List<Move__c> history = null;
	private static Map<String, List<Game_Piece__c>> alivepieces = null;
	private static Game__c game = null;
    private static List<boolean> setCastleRights = new List<boolean>{false, false, false, false};
    private static List<boolean> castleRights = new List<boolean>{false, false, false, false};
	
	public static final integer INVALID = 0;
	public static final integer VALID = 1;
	public static final integer KINGSIDE = 2;
	public static final integer QUEENSIDE = 3;
	public static final integer ENPASSANT = 4;
	public static final integer PROMOTION = 5;
	
	public static final integer CASTLE = 2;
	public static final integer NOCAPTURE = 3;
	public static final integer MUSTCAPTURE = 4;
	
	public static List<Game_Piece__c> getAlivePiecesByColor(ID game, String color) {
		return [SELECT ID, Piece_Type__c, Color__c, Current_Location__c, Current_Location__r.Name, Current_Location__r.Square__c, Current_Location__r.Square__r.Name FROM Game_Piece__c WHERE Game__c=:game AND Color__c=:color AND Current_Location__c!=NULL];
	}
	
	public static List<Game_Piece__c> getPieces (ID game) {
		return [SELECT ID, Current_Location__c, Color__c, Piece_Type__c, Piece__r.Initial_Location__c, Piece__r.Name FROM Game_Piece__c WHERE Game__c=:game ORDER BY Color__c DESC, Piece_Type__c, Piece__r.Initial_Location__r.Column__c];
	}
	
	public static List<Move__c> getHistory(ID game) {
		return [SELECT ID, Captured__c, Move_Number__c, End_Position__c, Piece__c, Piece__r.Color__c, Piece__r.Piece_Type__c, Start__r.Row__c, Start__r.Column__c, End__r.Row__c, End__r.Column__c, Special__c, Special_Detail__c FROM Move__c WHERE Game__c=:game ORDER BY Move_Number__c DESC];
	}
	
	public static List<Game_Square__c> getSquaresByRow(ID game, boolean blackPOV, integer row) {
		String direction = blackPOV?'DESC':'ASC';
		String fields = 'ID, Row__c, Column__c, Square__r.Name, Square__r.Color__c, Current_Occupant__r.Piece__c, Current_Occupant__r.Name, Current_Occupant__r.Piece__r.Name, Current_Occupant__r.Piece__r.Source__c, Current_Occupant__r.Piece__r.Color__c, Current_Occupant__c, Current_Occupant__r.Piece_Type__c, Current_Occupant__r.Source__c';
		List<Game_Square__c> result = Database.query('SELECT '+fields+' FROM Game_Square__c WHERE Game__c=:game AND Square__r.Row__c=:row ORDER BY Square__r.Column__c '+direction);
		return result;
	}
	
    @AuraEnabled
	public static Game__c getGame(ID gameid) {
		return [SELECT ID, Name, Game_Number__c, Already_Claimed__c, Last_Draw_Claim__c, Finished_Moves__c, Result__c, Result_Detail__c, Active_Draw_Offer__c, Player_to_Move__c, Hypothetical_Player_to_Move__c, White_Player__c, Black_Player__c, Claim_Type__c FROM Game__c WHERE ID=:gameid];
	}
	
	public static List<Game_Square__c> getSquares(ID gameid) {
		return [SELECT ID, Row__c, Column__c, Square_Name__c, Square__r.Row__c, Square__r.Column__c, Current_Occupant__c, Current_Occupant__r.Piece__c, Current_Occupant__r.Color__c, Current_Occupant__r.Piece_Type__c, Current_Occupant__r.Piece__r.Source__c, Square__r.Name, Square__r.Color__c, Current_Occupant__r.Source__c, Current_Occupant__r.Piece__r.Color__c, Color__c FROM Game_Square__c WHERE Game__c=:gameid ORDER BY Row__c, Column__c];
	}
	
    @AuraEnabled
    public static List<Game_Square__c> getSquaresByName(ID gameid, List<String> names) {
        return [SELECT ID, Row__c, Column__c, Square_Name__c, Square__r.Row__c, Square__r.Column__c, Current_Occupant__c, Current_Occupant__r.Piece__c, Current_Occupant__r.Color__c, Current_Occupant__r.Piece_Type__c, Current_Occupant__r.Piece__r.Source__c, Square__r.Name, Square__r.Color__c, Current_Occupant__r.Source__c, Current_Occupant__r.Piece__r.Color__c FROM Game_Square__c WHERE Game__c=:gameid AND Square_Name__c IN :names];
    }
    
	public static void initData(ID gameid) {
        if (!initialized) {
            squares = getSquares(gameid);
            squareMap = new Map<ID,Game_Square__c>();
            for (Game_Square__c square: squares) {
                squareMap.put(square.ID, square);
            }
            pieces = getPieces(gameid);
            pieceMap = new Map<ID,Game_Piece__c>();
            for (Game_Piece__c piece: pieces) {
                pieceMap.put(piece.ID, piece);
            }
            history = getHistory(gameid);
            alivepieces = new Map<String,List<Game_Piece__c>>();
            alivepieces.put('White', getAlivePiecesByColor(gameid, 'White'));
            alivepieces.put('Black', getAlivePiecesByColor(gameid, 'Black'));
            game = getGame(gameid);
            initialized = true;
        }
	}
    
    public static boolean canCastle(ID gameid, boolean white, boolean kingside) {
        integer index = (white?0:2)+(kingside?0:1);
        if (!setCastleRights[index]) {
            String side = kingside?'King':'Queen';
            String color = white?'White':'Black';
            String king = color+' King';
            String rook = color+' '+side+'\'s Rook';
            List<String> pieces = new List<String>{king, rook};
            List<Move__c> moves = [SELECT ID FROM Move__c WHERE Game__c=:gameid AND Piece__r.Name IN :pieces];
            boolean result = (moves.size() == 0);
            setCastleRights[index] = true;
            castleRights[index] = result;
            return result;
        } else {
            return castleRights[index];
        }
    }
    
    @AuraEnabled
	public static List<List<Game_Square__c>> getSquaresAs2dArray(ID game, ID userid, boolean blackPOV) {
		List<List<Game_Square__c>> squares = new List<List<Game_Square__c>>();
		for (integer i = 1; i <= 8; i ++) {
			squares.add(getSquaresByRow(game, blackPOV, blackPOV?i:9-i));
		}
		return squares;
	}
	
	@AuraEnabled
	public static String getTurn(ID gameid, ID userid) {
        return getTurn(gameid, userid, false);
    }
    
    public static String getTurn(ID gameid, ID userid, boolean hypothetical) {
		if (game == null) {
			game = getGame(gameid);
		}
		return hypothetical?game.Hypothetical_Player_to_Move__c:game.Player_to_Move__c;
	}
	
	public static Move__c getLastMove(ID game) {
		try {
			return history[0];
		} catch (System.ListException e) { //only happens if no moves have occurred yet.
			return null;
		}
	}
	
    @AuraEnabled
	public static String oppositeColor(String color) {
		return (color == 'White')?'Black':'White';
	}
	
	@AuraEnabled
	public static Game_Square__c getSquareByName(ID game, ID userid, String name) {
		if (squares == null) {
			squares = getSquares(game);
		}
		return getSquareByCoordinates(game, (name.charAt(1)-48), (name.charAt(0)-96));
	}
	
	public static Game_Square__c getSquareByCoordinates(ID game, integer row, integer column) {
		return squares[(row-1)*8+column-1];
	}
	
	public static Game_Square__c getSquareByCoordinates(ID game, decimal row, decimal column) {
		return getSquareByCoordinates(game, row.intValue(), column.intValue());
	}
	
    /*
     * This function updates the necessary Game_Square__c and Game_Piece__c records to move pieces, and returns a list of every altered Game_Square__c record.
     * When this function discovers that the attempted move is invalid, it immediately returns an empty list (no altered Game_Square__c records).
     * Returning an empty list like that is what this function's explanation means by 'invalidating a move'.
     * When this function refers to 'moving a piece', it consists of the following, not necessarily in order.
     *     1. Setting the piece's location to the destination square.
     *     2. Setting the destination square's occupant to the piece.
     *     3. Setting the starting square's occupant to null.
     *     4. If the move was a capture, setting the captured piece's location to null.
     * The function does the following in order:
     *     1. Invalidate any draw offer from the opponent of the player that just moved (maybe should be done after the move is validated?).
     *     2. Check that the move starts on a square occupied by a piece owned by the correct player- otherwise, invalidate the move.
     *     3. Run the move through "isValidMove" and get the return value.
     *         a. That can be any of 6 codes that describe the validity of the move.
     *         b. Most inputs to "isValidMove" will return INVALID or VALID, but a few will return something else, which means the move is valid but requires extra steps to complete.
     *     4. Get data about any piece at the destination square. If the move is valid, this piece will be captured.
     *     5. Check the value returned by "isValidMove" and perform actions based on that value.
     *     6. Update all changes not already updated.
     *     7. Call "publishAndRecordMove" to create the Move__c record and Chess_Piece_Move__e event.
     */
	@AuraEnabled
	public static List<Game_Square__c> move(ID gameid, ID userid, Game_Square__c start, Game_Square__c destination) {
		initData(gameid);
        Game__c game = getGame(gameid);
        /*
         * If a player makes a move while there's an active draw offer by their opponent, it qualifies as rejecting the offer.
         */
        if (game.Active_Draw_Offer__c != null && game.Active_Draw_Offer__c != userid) {
            game.Active_Draw_Offer__c =  null;
            game.Claim_Type__c = null;
            update game;
        }
        List<Game_Square__c> result = new List<Game_Square__c>();
		Game_Piece__c piece = pieceMap.get(start.Current_Occupant__c);
        /*
         * Invalidates any move that starts on a blank square or a square occupied by a wrong-color piece.
         */
        if (piece == null || piece.Color__c != getTurn(gameid, userid)) {
            return result;
        }
		integer code = isValidMove(gameid, piece, start, destination);
		boolean capture = (destination.Current_Occupant__c != null);
        Game_Piece__c captured = null;
        String special = '';
        String specialDetail = '';
		if (code == INVALID) {
			return result;
		} else if (code == VALID) {
			//blank because nothing special has to happen if the move is valid.
		} else if (code == KINGSIDE || code == QUEENSIDE) {
            boolean isKingSide = (code==KINGSIDE);
            special = 'Castle';
            specialDetail = isKingSide?'Kingside':'Queenside';
            integer rookStartColumn = isKingSide?8:1;
            integer rookDestColumn = isKingSide?6:4;
            integer row = start.Row__c.intValue();
			Game_Square__c rookstart = getSquareByCoordinates(gameid, row, rookstartcolumn);
            Game_Square__c rookdestination = getSquareByCoordinates(gameid, row, rookdestcolumn);
            Game_Piece__c rook = rookstart.Current_Occupant__r;
            relocatePiece(gameid, rook, rookstart, rookdestination);
            result.add(rookstart);
            result.add(rookdestination);
		} else if (code == ENPASSANT) {
            special = 'En Passant';
            specialDetail = (destination.Column__c>start.Column__c)?'Kingside':'Queenside';
			Game_Square__c capturedSquare = getSquareByCoordinates(gameid, start.Row__c, destination.Column__c);
            captured = capture(gameid, capturedSquare, true);
            result.add(capturedSquare);
		} else if (code == PROMOTION) {
            special = 'Promotion';
            specialDetail = 'Undecided';
		}
        
        if (code != ENPASSANT) {
        	captured = capture(gameid, destination, false);
        }
        relocatePiece(gameid, piece, start, destination);
        ID capturedID = (captured==null)?null:(captured.Piece__c);
        publishAndRecordMove(gameid, piece, start, destination, capturedID, special, specialDetail, result);
        return result;
    }
	
    /*
     * Blindly moves a piece from start to destination.
     */
    public static void relocatePiece(ID gameid, Game_Piece__c piece, Game_Square__c start, Game_Square__c destination) {
        start.Current_Occupant__c = null;
        destination.Current_Occupant__c = piece.ID;
        piece.Current_Location__c = destination.ID;
        update start;
        update destination;
        update piece;
    }
    
    /*
     * Blindly sets a piece's location to null.
     * Also sets the square's occupant to null if "isEnPassant" is set.
     */
    public static Game_Piece__c capture(ID gameid, Game_Square__c square, boolean isEnPassant) {
        if (square.Current_Occupant__c == null) {
            return null;
        } else {
            Game_Piece__c captured = pieceMap.get(square.Current_Occupant__c);
            captured.Current_Location__c = null;
            if (isEnPassant) {
                square.Current_Occupant__c = null;
                update square;
            }
            update captured;
            return captured;
        }
    }
    
    /*
     * This function returns a list containing two lists, both containing valid moves of the piece passed in.
     * The first sublist is the list of moves for which the result of calling "isValidMove" returns VALID.
     * The second sublist is the list of moves for which the result of calling "isValidMove" returns something other than INVALID or VALID.
     *     In other words, possible moves that involve special circumstances. Castling, promotion, or en passant.
     */
    @AuraEnabled
    public static List<List<Game_Square__c>> getValidMoves (ID gameid, ID userid, Game_Piece__c mover, Game_Square__c start) {
        initData(gameid);
        List<List<Game_Square__c>> result = new List<List<Game_Square__c>>();
        List<Game_Square__c> unqualified = new List<Game_Square__c>();
        List<Game_Square__c> qualified = new List<Game_Square__c>();
        for (Game_Square__c square: getSquares(gameid)) {
            integer code = isValidMove(gameid, mover, start, square);
            if (code == INVALID) {
                continue;
            } else if (code == VALID) {
                unqualified.add(square);
            } else {
                qualified.add(square);
            }
        }
        result.add(unqualified);
        result.add(qualified);
        return result;
    }
    
	/*
	 * Checks if move is valid.
	 * Usually returns INVALID or VALID, but can return something else (enumerated below).
	 * The other codes mean that the move is valid but require extra action by the caller to complete.
	 * The codes this can return are:
	 *     INVALID: invalid move
	 *     MOVE: valid move
	 *     KINGSIDE: valid as a kingside castle (requires moving the correct rook to complete)
	 *     QUEENSIDE: valid as a queenside castle (requires moving the correct rook to complete)
	 *     ENPASSANT: valid as an en passant (requires capturing the correct pawn to complete)
	 *     PROMOTION: valid as a promotion (requires promoting the pawn to complete)
	 */
	@AuraEnabled
	public static integer isValidMove (ID gameid, Game_Piece__c mover, Game_Square__c start, Game_Square__c destination) {
		integer validation = validatePath(mover.Piece_Type__c, mover.Color__c, start.Square__r, destination.Square__r);
		integer result;
        if (validation == INVALID) {
            return INVALID;
        } else if (validation == VALID) {
            result = VALID;
        } else if (validation == CASTLE) {
            //kingside or queenside castle
            result = (start.Column__c>destination.Column__c)?QUEENSIDE:KINGSIDE;
            Game_Square__c intermediate = getSquareByCoordinates(gameid, start.Row__c, (destination.Column__c+start.Column__c)/2);
            Game_Square__c rookstart = getSquareByCoordinates(gameid, start.Row__c, (result==QUEENSIDE)?1:8);
            Game_Piece__c rook = pieceMap.get(rookstart.Current_Occupant__c);
            //validate that rook square is occupied by the piece that started there
            if (rook == null || (squareMap.get(rook.Current_Location__c).Square__c != rook.Piece__r.Initial_Location__c)) {
                return INVALID;
            }
            //validate that both pieces have not yet moved
            if (!canCastle(gameid, mover.Color__c=='White', result==KINGSIDE)) {
                return INVALID;
            }
            /*
             * Validates that all intermediate squares are empty.
             * This is the one call to hasClearPath where the data has not been cleared by validatePath.
             *     However, the piece passed is always a rook, and the squares are both one of 4 known values, all of which would return VALID if validatePath was called. 
             * hasClearPath will be called for the king later, making this partially redundant. However, there are two things that doesn't account for.
             *     1. b1 or b8 in the case of a queenside castle.
             *     2. An enemy piece on the king's post-castle square.
             * When closing that gap, it's easier to check all the squares at once, even if some get checked twice.
             */
            if (!hasClearPath(gameid, rook, rookstart, start, true)) {
                return INVALID;
            }
            List<Game_Piece__c> enemies = alivePieces.get(oppositeColor(mover.Color__c));
            for (Game_Piece__c enemy: enemies) {
                //cannot start in check when castling
                if (threatensSquare(gameid, enemy, squareMap.get(enemy.Current_Location__c), start)) {
                    return INVALID;
                }
                //cannot castle through check
                if (threatensSquare(gameid, enemy, squareMap.get(enemy.Current_Location__c), intermediate)) {
                    return INVALID;
                }
            }
        } else if (validation == NOCAPTURE) {
            if (destination.Current_Occupant__c == null) {
                Set<integer> ends = new Set<integer>{1,8};
                result = ends.contains(destination.Row__c.intvalue())?PROMOTION:VALID;
            } else {
                return INVALID;
            }
        } else if (validation == MUSTCAPTURE) {
            if (destination.Current_Occupant__c != null) {
                Set<integer> ends = new Set<integer>{1,8};
                result = ends.contains(destination.Row__c.intvalue())?PROMOTION:VALID;
            }
            else {
                /*
                 * If control reaches here, that means the move path requires capturing but the destination square is unoccupied.
                 * However, the move can still be valid under one condition- if it's a valid en passant.
                 * That's what this block checks.
                 */
                Move__c last = getLastMove(gameid);
                //en passant can never be the first move
                if (last == null) {
                    return INVALID;
                }
                /*
                 * The next 4 'if' statements check if the last move was correct for en passant by the desired pawn.
                 * A valid en passant must pass all of them.
                 * In order, the checks are:
                 *     1. The last piece that moved was a pawn.
                 *     2. The last move was a doublestep.
                 *     3. The last move ended on the same row as the current piece is starting on.
                 *     4. The last move ended on the same column as the desired move is ending on.
                 * There's no need to manually validate that the moving pawn is starting in the correct row, since that logically follows from the first 3 checks.
                 */
                if (last.Piece__r.Piece_Type__c != 'Pawn') {
                    return INVALID;
                }
                if (Math.abs(last.End__r.Row__c-last.Start__r.Row__c) != 2) {
                    return INVALID;
                }
                if (last.End__r.Row__c != start.Row__c) {
                    return INVALID;
                }
                if (last.End__r.Column__c != destination.Column__c) {
                    return INVALID;
                }
                result = ENPASSANT;
            }
        }
		if (!hasClearPath(gameid, mover, start, destination, false)) {
			return INVALID;
		}
		if (!protectsKing(gameid, mover, start, destination, result==ENPASSANT)) {
			return INVALID;
		}
		return result;
	}
	
	/* 
	 * Checks if a move follows the path of a piece.
	 * For example, if the piece is a rook, this function validates that the move is horizontal or vertical.
	 * Only checks if the move is theoretically possible- not whether there's a piece in the way or the king is in check.
	 * Returns a code describing the validity of the move. The most common codes are INVALID and VALID.
	 * Other codes mean there's extra steps to determine if the path is valid, or to execute the move.
	 * The codes that this function can return are:
	 *     INVALID: invalid path
	 *     VALID: valid path
	 *     CASTLE: valid path if castling
	 *     NOCAPTURE: valid path only if not capturing
	 *     MUSTCAPTURE: valid path only if capturing
	 */
	public static integer validatePath(String pieceType, String color, Square__c start, Square__c destination) {
		//in case of bug that allows this
		if ((start.Column__c == destination.Column__c) && (start.Row__c == destination.Row__c)) {
			return INVALID;
		}
		switch on pieceType {
			when 'King' {
				//check if move is only one square
				if ((Math.abs(start.Column__c - destination.Column__c) <= 1) && (Math.abs(start.Row__c - destination.Row__c) <= 1)) {
					return VALID;
				}
                /*
                 * The next 4 'if' statements check if it could be a valid castle.
                 * A move will pass all of these if and only if it is a valid castle.
                 * The checks are as follows:
                 *     1. The move starts in the correct column.
                 *     2. The move ends in one of the two correct columns.
                 *     3. The start and end are in the same row.
                 *     4. The move starts in the correct row. 
				 */
				if (start.Column__c != 5) {
					return INVALID;
				}
				if (destination.Column__c != 3 && destination.Column__c != 7) {
					return INVALID;					
				}
				if (start.Row__c != destination.Row__c) {
					return INVALID;
				}
				if (!((color == 'White' && start.Row__c == 1) || (color == 'Black' && start.Row__c == 8))) {
					return INVALID;
				}
				return CASTLE;
			} when 'Queen' {
				return (
					(Math.abs(start.Column__c-destination.Column__c) == Math.abs(start.Row__c-destination.Row__c)) || //diagonal
					(start.Column__c == destination.Column__c) || //horizontal
					(start.Row__c == destination.Row__c) //vertical
				)?VALID:INVALID;
			} when 'Rook' {
				return (
					(start.Column__c == destination.Column__c) || //horizontal
					(start.Row__c == destination.Row__c) //vertical
				)?VALID:INVALID;
			} when 'Knight' {
				return (
					((Math.abs(start.Column__c-destination.Column__c) + Math.abs(start.Row__c-destination.Row__c)) == 3) && //rules out any invalid move except 3-square orthogonal moves
					(start.Column__c != destination.Column__c) && //rules out vertical moves
					(start.Row__c != destination.Row__c) //rules out horizontal moves
				)?VALID:INVALID;
			} when 'Bishop' {
				return (
					(Math.abs(start.Column__c-destination.Column__c) == Math.abs(start.Row__c-destination.Row__c)) //diagonal
				)?VALID:INVALID;
			} when 'Pawn' {
				integer direction = (color=='White')?1:-1;
				decimal coldiff = Math.abs(start.Column__c-destination.Column__c);
				if (coldiff > 1) { //rules out moves that have too big of a horizontal component
					return INVALID;
				}
				//validates all moves that are 1 step forward, capture or not
				if ((start.Row__c+direction)==destination.Row__c) {
					return (coldiff==1)?MUSTCAPTURE:NOCAPTURE;
				}
				/*
				 * Like with the king's castle, the next 3 'if' statements check if the move could be a valid doublestep
				 * A move will pass all of these if and only if it is a valid doublestep.
				 * The checks are as follows:
				 *     1. The move ends in the same column as it started- no horizontal part.
				 *     2. The end square is two steps in the correct direction from the starting square.
				 *     3. The starting square is in the correct row.
				 */
				if (coldiff != 0) {
					//no horizontal motion
					return INVALID;
				}
				if ((start.Row__c+2*direction)!=destination.Row__c) {
					//2 square step
					return INVALID;
				}
				if ((2*start.Row__c+5*direction)!=9) {
					//starting on the correct (starting) square
					//the equation will only come out to 9 for a white pawn in row 2 (2*2+5*1), or a black pawn in row 7 (2*7+5*(-1))
					return INVALID;
				}
				return NOCAPTURE;
			}
		}
		return INVALID;
	}

    /*
     * This is a version of hasClearPath with fewer parameters than the full one.
     * It exists because the most common way the function is called is also a little cumbersome to call, so it's shortened to this.
     */
	public static boolean hasClearPath (ID gameid, Game_Piece__c mover, Game_Square__c start, Game_Square__c destination, boolean ignoreOccupant) {
		Set<Game_Square__c> emptySet = new Set<Game_Square__c>();
		return hasClearPath(gameid, mover, start, destination, emptySet, emptySet, ignoreOccupant);
	}
	
    /*
     * This function checks whether the path between two squares is clear. This consists of:
     * 	   If there's a friendly piece at the destination (unless ignoreOccupant is set- see below).
     * 	   If there's a piece in between the start and destination (unless the piece is a knight).
     * This function does not check whether the piece could move to the destination- for example, it could return true if passed a rook and 2 squares diagonal from each other.
     *     However, as of writing this, no instance of this call passes such data- they all get checked through validatePath first.
     * It also does not check whether the move keeps the king safe.
     * The two parameters that are sets are for pretending a square is occupied or not for the purposes of the function.
     * 	   This is usually for checking if a move would result in the friendly king being in check.
     * 	   They will most often be empty sets.
     *     The other function with the same name as this passes the empty set for both by default.
     * ignoreOccupant tells the function whether to account for someone on the destination square or not.
     * 	   This was to fix a bug where a king could capture a protected enemy piece.
     * 	   That happened because this function said the protecting piece didn't have a clear path to the protected one, due to the square being occupied by a friendly piece.
     * 	   This made it seem like that square was safe for the king.
     * ignoreOccupant will be false when evaluating if a piece can move somewhere, but true when evaluating if a piece threatens/defends a square.
     * This function may return bogus data if "start" and "destination" aren't either horizontal, vertical, or diagonal from each other.
     *     However, as mentioned earlier, this doesn't happen unless the piece is a knight, which is handled before other cases.
	 */
	public static boolean hasClearPath (ID gameid, Game_Piece__c mover, Game_Square__c start, Game_Square__c destination, Set<Game_Square__c> whatIfEmpty, Set<Game_Square__c> whatIfFull, boolean ignoreOccupant) {
		if ((!ignoreOccupant) && (destination.Current_Occupant__c != null) && (destination.Current_Occupant__r.Color__c == mover.Color__c)) {
			return false;
		}
		if (mover.Piece_Type__c == 'Knight') {
			return true;
		}
        decimal deltaRow = destination.Row__c-start.Row__c;
        decimal deltaColumn = destination.Column__c-start.Column__c;
        /*
         * Math.signum takes a number and returns 1 if it's positive, -1 if it's negative, or 0 if it's 0.
         * "vdirection" is -1 for moving towards white, 1 for towards black, 0 for a purely horizontal move.
         * "hdirection" is -1 for moving queenside, 1 for kingside, 0 for a purely vertical move.
         * If both "vdirection" and "hdirection" are non-zero, the move is diagonal.
         */
		integer vdirection = (Math.signum(deltaRow)).intValue();
		integer hdirection = (Math.signum(deltaColumn)).intValue();
		integer distance = (Math.max(Math.abs(deltaRow), Math.abs(deltaColumn))).intValue();
		for (integer i = 1; i < distance; i ++) {
            /*
             * "intermediate" is the Game_Square__c a distance of "i" from the starting square in the direction of the destination square.
             */
			Game_Square__c intermediate = getSquareByCoordinates(gameid, start.Row__c+(i*vdirection), start.Column__c+(i*hdirection));
			if (whatIfFull.contains(intermediate) || (intermediate.Current_Occupant__c != null && !whatIfEmpty.contains(intermediate))) {
				return false;
			}
		}
		return true;
	}
	
	/*
	 * Returns true if and only if the move doesn't result in the friendly king being in check.
	 * Does not check if a move is valid, just that it doesn't expose the king.
	 * However as of writing this, all inputs to this are already validated through validatePath and hasClearPath.
	 * isEnPassant tells the function that the intended move is an en passant and to account for the en passanted pawn missing.
	 *     isEnPassant is usually false.
	 *     The function does not validate that the data that goes with "isEnPassant" is actually a valid en passant.
	 *         However, all calls to this pass data that's already been validated as a possible en passant.
	 */
	public static boolean protectsKing (ID gameid, Game_Piece__c mover, Game_Square__c start, Game_Square__c destination, boolean isEnPassant) {
		Set<Game_Square__c> whatIfEmpty = new Set<Game_Square__c>();
		Set<Game_Square__c> whatIfFull = new Set<Game_Square__c>();
		Game_Square__c kingsquare;
		String color = mover.Color__c;
        ID enPassanted = null;
		if (mover.Piece_Type__c == 'King') {
			kingsquare = destination;
		} else {
			kingsquare = [SELECT ID, Column__c, Row__c, Square__r.Column__c, Square__r.Row__c FROM Game_Square__c WHERE Game__c=:gameid AND Current_Occupant__r.Color__c=:color AND Current_Occupant__r.Piece_Type__c='King'];
		}
        /*
         * To determine if a move protects the king, there are 3 things the calculation needs to account for.
         *     1. The current location of the moving piece being empty.
         *     2. The destination of the moving piece being occupied.
         *     3. The absence of a prospective captured piece.
         * It does not, however need to account for the position change of rook getting castled.
         * This is because it's impossible to come up with a position where:
         *     1. The rook's change of position changes whether the king's post-castle square is safe, AND
         *     2. The king's pre-castle square and the rook's post-castle square are both safe prior to castling (One of the requirements for castling).
         */
		whatIfEmpty.add(start);
		whatIfFull.add(destination);
		if (isEnPassant) {
            Game_Square__c victimSquare = getSquareByCoordinates(gameid, start.Row__c, destination.Column__c);
			whatIfEmpty.add(victimSquare);
            enPassanted = victimSquare.Current_Occupant__c;
		}
		List<Game_Piece__c> enemies = getAlivePiecesByColor(gameid, oppositeColor(mover.Color__c));
		for (Game_Piece__c enemy: enemies) {
            //Skips any piece that would be captured by the move.
            boolean captured = (enemy.Current_Location__c == destination.ID) || (enemy.ID == enPassanted);
            if (!captured && threatensSquare(gameid, enemy, squareMap.get(enemy.Current_Location__c), kingsquare, whatIfEmpty, whatIfFull)) {
				return false;
			}
		}
		return true;
	}
    
    public static boolean threatensSquare(ID gameid, Game_Piece__c mover, Game_Square__c start, Game_Square__c destination) {
		Set<Game_Square__c> empty = new Set<Game_Square__c>();
		return threatensSquare(gameid, mover, start, destination, empty, empty);
	}
	
    /*
     * Checks if a piece threatens a square (making that square unavailable to the enemy king).
     * Does not check whether the corresponding move would expose the king.
	 * the last two parameters are for pretending a square is occupied or not for the purposes of the function
	 *     usually for the purpose of checking if a move would result in the friendly king being in check
	 *     they will most often be empty sets
	 */
	public static boolean threatensSquare (ID gameid, Game_Piece__c mover, Game_Square__c start, Game_Square__c destination, Set<Game_Square__c> whatIfEmpty, Set<Game_Square__c> whatIfFull) {
		Set<integer> threatcodes = new Set<integer>{VALID,MUSTCAPTURE};
		return (
            threatcodes.contains(validatePath(mover.Piece_Type__c, mover.Color__c, start.Square__r, destination.Square__r)) &&
            hasClearPath(gameid, pieceMap.get(mover.ID), squareMap.get(start.ID), squareMap.get(destination.ID), whatIfEmpty, whatIfFull, true)
        );
	}
    
    /*
     * This function was spawned when "move" got bloated with both the responsiblity of changing piece and square data and recording the move.
     * So instead of "move" having all those responsibilities, it handles updating the Game_Square__c and Game_Piece__c records, then calls this function.
     * When this function is called, "move" has already determined the move to be a valid one, so this function doesn't need to (and would get bloated if it tried).
     * This function does the following in order:
     *     1. Calculate which of the 4 original rights to castle still exist.
     *     2. Simultaneously:
     *         a. Find which pawn, if any, can be en passanted, AND
     *         b. Build a string representing the position after the move. This string DOES NOT follow the FEN standard.
     *     3. Append characters representing the rights to castle and right to en passant to the end of the string.
     *     4. Get data about each square in "moveResult", and simultaneously:
     *         a. Repopulate "moveResult" with that data. This adds information about the Game_Square__c objects that the client-side caller can use, AND
     *         b. Add that information to "eventString"
     *     5. Create and insert the Move__c record corresponding to the move being executed.
     *     6. Create and publish the necessary Chess_Piece_Move__e event.
     */
    public static void publishAndRecordMove(ID gameid, Game_Piece__c piece, Game_Square__c start, Game_Square__c destination, ID capturedID, String special, String specialDetail, List<Game_Square__c> moveResult) { 
        initialized = false;
        initdata(gameid);
        String endPosition = '';
        String eventString = 'M';
		String opponent = piece.Color__c;
        String activePlayer = oppositeColor(opponent);
        //if this seems backwards, it's because it corresponds to the move that just happened.
        //it's to check if a piece that just moved can be en-passanted
        integer pawnStartRow = (opponent=='White')?2:7;
        integer pawnDoublestepRow = (opponent=='White')?4:5;
        integer rightToCastle = 0;
        String name = pieceMap.get(piece.ID).Piece__r.Name;
        if (name != 'Black King') {
            if (name != 'Black Queen\'s Rook') {
            	rightToCastle += canCastle(gameid, false, false)?8:0;
            }
            if (name != 'Black King\'s Rook') {
            	rightToCastle += canCastle(gameid, false, true)?4:0;
            }
        }
        if (name != 'White King') {
            if (name != 'White Queen\'s Rook') {
            	rightToCastle += canCastle(gameid, true, false)?2:0;
            }
            if (name != 'White King\'s Rook') {
            	rightToCastle += canCastle(gameid, true, true)?1:0;
            }
        }
        String rightToEnpassant = '-';
        //true if the move just made was a pawn doublestep
        boolean possibleRightToEnpassant = (piece.Piece_Type__c == 'Pawn' && start.Row__c == pawnStartRow && destination.Row__c == pawnDoublestepRow);
        Set<decimal> castleRows = new Set<decimal>{1,8};
        for (Game_Square__c square: squares) {
            /*
             * series of conditions to check for the right to en passant
             * the conditions in plain English are as follows:
             *     1. Check possibleRightToEnpassant, which tells if the last move was a doublestep.
             *     2. Check if the current square is on the correct row.
             *     3. Check if the current square is in one of the two correct columns.
             *     4. Check that the square is occupied. This may seem redundant with 5 and 6, but this step prevents a NullPointerException.
             *     5. Check that the square is occupied by a pawn.
             *     6. Check that the square occupant is the right color.
             *     7. Check that performing the move would not expose the king.
             */
            if (possibleRightToEnpassant 
                	&& (square.Row__c == destination.Row__c)
                	&& (Math.abs(square.Column__c-destination.Column__c) == 1)
                	&& (square.Current_Occupant__c != null)
                	&& (square.Current_Occupant__r.Piece_Type__c == 'Pawn')
                	&& (square.Current_Occupant__r.Color__c == activePlayer) 
                	&& (protectsKing(gameid, pieceMap.get(square.Current_Occupant__c), square, getSquareByCoordinates(gameid, (pawnStartRow+pawnDoubleStepRow)/2, destination.Column__c), true))
                ) {
                    if (rightToEnpassant == '-') {
                        rightToEnpassant = String.fromCharArray(new List<Integer>{square.Column__c.intValue()+96});
                    } else {
                        rightToEnpassant = String.fromCharArray(new List<Integer>{destination.Column__c.intValue()+64});
                        possibleRightToEnpassant = false; //to prevent further checks here once it's known that none are possible
                    }
            }
            if (square.Current_Occupant__c == null) {
                endPosition += '-';
            } else {
                String pieceType = square.Current_Occupant__r.Piece_Type__c;
                String pieceCode = (pieceType=='Knight')?'N':pieceType.substring(0, 1);
                if (square.Current_Occupant__r.Color__c == 'Black') {
                    pieceCode = pieceCode.toLowerCase();
                }
                endPosition += pieceCode;
            }
        }
        String rightToCastleCharacter = (rightToCastle < 10)?String.valueOf(rightToCastle):String.fromCharArray(new List<Integer> {rightToCastle+55});
        endPosition += (rightToCastleCharacter + rightToEnpassant);
        moveResult.add(start);
        moveResult.add(destination);
        for (integer i = 0; i < moveResult.size(); i ++) {
            ID current = moveResult[i].ID;
            moveResult[i] = [SELECT ID, Row__c, Column__c, Square_Name__c, Square__r.Row__c, Square__r.Column__c, Current_Occupant__c, Current_Occupant__r.Piece__c, Current_Occupant__r.Color__c, Current_Occupant__r.Piece_Type__c, Current_Occupant__r.Piece__r.Source__c, Square__r.Name, Square__r.Color__c, Current_Occupant__r.Source__c, Current_Occupant__r.Piece__r.Color__c FROM Game_Square__c WHERE ID=:current];
            eventString += moveResult[i].Square_Name__c;
        }
        Move__c record = new Move__c(
            Move_Number__c = history.size(),
            Game__c = gameid,
            Piece__c = piece.Piece__c,
            Start__c = start.Square__c,
            End__c = destination.Square__c,
            Captured__c = capturedID,
            Special__c = special,
            Special_Detail__c = specialDetail,
            End_Position__c = endPosition
        );
        insert record;
        Chess_Piece_Move__e moveEvent = new Chess_Piece_Move__e(Squares__c=eventString, Game_Number__c=Integer.valueOf(game.Game_Number__c));
        Database.SaveResult eventResult = EventBus.publish(moveEvent);
        System.debug('Publish: ');
        System.debug(eventResult.isSuccess());
	}
    
    /*
     * Returns the name of the square occupied by the king in check.
     * Returns '' if no king is in check.
	 */
    @AuraEnabled
    public static String getCheckSquare(ID gameid, ID userid) {
        initData(gameid);
        String turn = getTurn(gameid, userid, true);
        if (turn == '') {
            return '';
        }
        Game_Square__c kingsquare = [SELECT ID FROM Game_Square__c WHERE Game__c=:gameid AND Current_Occupant__r.Piece_Type__c='King' AND Current_Occupant__r.Color__c=:turn];
        kingsquare = squareMap.get(kingsquare.ID);
        for (Game_Piece__c piece: getAlivePiecesByColor(gameid, oppositeColor(turn))) {
            if (threatensSquare(gameid, piece, squareMap.get(piece.Current_Location__c), kingsquare)) {
                return kingsquare.Square_Name__c;
            }
        }
        return '';
    }
	
	/*
	 * Returns the ID of the pawn that reached the last rank but where the promotion is not yet decided.
	 * Returns null if no pawn fits that bill.
	 */     
    @AuraEnabled
    public static ID getPendingPromotion(ID gameid, ID userid) {
        initdata(gameid);
        Move__c last = getLastMove(gameid);
        if ((last == null || (last.Special_Detail__c != 'Undecided'))) {
            return null;
        } else {
            Game_Piece__c pawn = [SELECT ID FROM Game_Piece__c WHERE Game__c=:gameid AND Piece__c=:last.Piece__c];
            return pawn.ID;
        }
    }
    
    /*
     * Converts (promotes) a pawn on the last rank to the desired piece type.
     */
    @AuraEnabled
    public static Game_Square__c promotePawn(ID gameid, ID userid, ID pawnid, String promoteTo) {
        Game_Piece__c pawn = [SELECT ID, Current_Location__c FROM Game_Piece__c WHERE ID=:pawnid];
        Game__c game = getGame(gameid);
        pawn.Promoted__c = promoteTo;
        Move__c move = [SELECT ID, End__c, End__r.Row__c, End__r.Column__c, End__r.Name, End_Position__c, Piece__r.Color__c FROM Move__c WHERE Game__c=:gameid AND Special_Detail__c='Undecided'];
        List<Integer> endPosition = move.End_Position__c.getChars();
        move.Special_Detail__c = promoteTo;
        integer promotion = promoteTo=='Knight'?78:promoteTo.charAt(0); //78 is ascii for 'N'
        if (move.Piece__r.Color__c == 'Black') {
            promotion += 32; //convert to lowercase
        }
        //update the correct character of the last move to reflect what the pawn was promoted to.
        endPosition[((move.End__r.Row__c-1)*8+(move.End__r.Column__c-1)).intValue()] = promotion;
        move.End_Position__c = String.fromCharArray(endPosition);
        update pawn;
        update move;
        String eventString = 'P'+move.End__r.Name;
        Chess_Piece_Move__e moveEvent = new Chess_Piece_Move__e(Squares__c=eventString, Game_Number__c=Integer.valueOf(game.Game_Number__c));
        Database.SaveResult eventResult = EventBus.publish(moveEvent);
        System.debug('Publish: ');
        System.debug(eventResult.isSuccess());
        return [SELECT ID, Row__c, Column__c, Square_Name__c, Square__r.Row__c, Square__r.Column__c, Current_Occupant__c, Current_Occupant__r.Piece__c, Current_Occupant__r.Color__c, Current_Occupant__r.Piece_Type__c, Current_Occupant__r.Piece__r.Source__c, Square__r.Name, Square__r.Color__c, Current_Occupant__r.Source__c, Current_Occupant__r.Piece__r.Color__c FROM Game_Square__c WHERE Current_Occupant__c=:pawnid];
    }
    
    /*
     * Calls a function to check if the game is over.
     * If yes, fires a global event that ends the game, then returns the string representing it.
     * If no, returns '' and does nothing.
     * Called after every turn.
     */
    @AuraEnabled
    public static String setFinality(ID gameid, ID userid) {
        initdata(gameid);
        String eventString = calculateFinality(gameid, userid);
        if (eventString != '') {
            Chess_Piece_Move__e moveEvent = new Chess_Piece_Move__e(Squares__c=eventString, Game_Number__c=Integer.valueOf(game.Game_Number__c));
            Database.SaveResult eventResult = EventBus.publish(moveEvent);
            System.debug('Publish: ');
            System.debug(eventResult.isSuccess());
        }
        return eventString;
    }
    
    /*
     * Checks if the game is over.
     * If the game is over, sets the result and returns a string for a global event to announce that the game is over.
     * If the game is not over, this function returns '' and continues as normal.
     * There are 6 strings that could be returned if the game is over. They are:
     *     'D3': draw by 3-fold repetition
     *     'D50': draw by 50-move rule
     *     'DS': draw by stalemate
     *     'WWC': win for white by checkmate
     *     'WBC': win for black by checkmate
     *     'DI': draw by insufficient material
     * These aren't the only global event codes, but they are the only ones this function can return.
     * This function does the following in order:
     *     1. Checks if the last player to move made an "After my move" draw claim.
     *         a. If yes, checks the condition of the player's draw claim (3-fold repetition or 50 move rule).
     *         b. If the condition is true, sets the game result accordingly and returns the corresponding string (see above).
     *         c. Checking for "now" claims is not necessary as those are checked immediately.
     *     2. Iterates through the material of the player to move.
     *         a. Checks if the active player has sufficient material to mate (and if not, how much; maybe the opponent does)
     *         b. Checks each piece for any valid moves until it finds at least one.
     *     3. If the active player had no valid moves, checks if the active player's king is in check.
     *         a. If yes, sets the game result to win for the appropriate player by checkmate and returns the corresponding string (see above).
     *         b. If no, sets the game result to draw by stalemate and returns the corresponding string (see above).
     *     4. If the active player didn't have sufficient material for checkmate, iterates through teh opponent's material to see what they have.
     *         a. If the active and opposing player together have sufficient material for checkmate, returns '' and the game continues.
     *         b. Otherwise, sets the game result to draw by insufficient material and returns the corresponding string (see above).
     */
    public static String calculateFinality(ID gameid, ID userid) {
        boolean sufficient = false;
        boolean blackBishop = false;
        boolean whiteBishop = false;
        boolean bothBishops = false;
        boolean knight = false;
        boolean hasValidMoves = false;
		String eventString = '';
        String turn = getTurn(gameid, userid, true);
        String opposite = oppositeColor(turn);
        Game__c game = getGame(gameid);
        List<Game_Piece__c> activematerial = getAlivePiecesByColor(gameid, turn);
        List<Game_Piece__c> enemymaterial = getAlivePiecesByColor(gameid, opposite);
        String claim = game.Claim_Type__c;
        /*
         * This loop checks two things:
         *     1. Whether the active player has sufficient material for checkmate.
         *     2. Whether the active player has any valid moves.
         */
        for (Game_Piece__c piece: activematerial) {
            if (!hasValidMoves) {
                List<List<Game_Square__c>> validMoves = getValidMoves(gameid, userid, pieceMap.get(piece.ID), squareMap.get(piece.Current_Location__c));
                if ((validMoves[0].size()+validMoves[1].size())>=1) {
                    hasValidMoves = true;
                }
            }
            if (!sufficient) {
                switch on piece.Piece_Type__c {
                    when 'Queen' {
                        sufficient = true;
                    } when 'Rook' {
                        sufficient = true;
                    } when 'Pawn' {
                        sufficient = true;
                    } when 'Knight' {
                        if (knight || blackbishop || whitebishop) {
                            sufficient = true;
                        } else {
                            knight = true;
                        }
                    } when 'Bishop' {
                        Game_Square__c bishopSquare = squareMap.get(piece.Current_Location__c);
                        if (!blackbishop && bishopSquare.Color__c == 'Black') {
                            blackbishop = true;
                        }
                        if (!whitebishop && bishopSquare.Color__c == 'White') {
                            whitebishop = true;
                        }
                        bothbishops = (whitebishop && blackbishop);
                        if (bothbishops || knight) {
                            sufficient = true;
                        }
                    }
                }
            }
            if (sufficient && hasValidMoves) {
                /*
                 * The purpose of the for loop is to check if the active player has sufficient material for checkmate and at least one valid move.
                 * Once both are found, there's no need to keep checking for it.
                 */
                break;
            }
        }
        /*
         * This statement handles what happens when the active player has no valid moves.
         * When that happens, the game ends in either checkmate or stalemate.
         * This block makes the necessary checks for that, ends the game, and returns from the function.
         */
        if (!hasValidMoves) {
            boolean checkmate = false;
            Game_Square__c kingsquare = [SELECT ID FROM Game_Square__c WHERE Game__c=:gameid AND Current_Occupant__r.Piece_Type__c='King' AND Current_Occupant__r.Color__c=:turn];
            for (Game_Piece__c enemy: enemyMaterial) {
                if (threatensSquare(gameid, pieceMap.get(enemy.ID), squareMap.get(enemy.Current_Location__c), squareMap.get(kingsquare.ID))) {
                    checkmate = true;
                    break;
                }
            }
            if (checkmate) {
                boolean whiteWin = opposite=='White';
                setResult(gameid, whiteWin?'1-0':'0-1', 'Checkmate');
                eventString = 'W'+(whiteWin?'W':'B')+'C';
            } else {
                setResult(gameid, '.5-.5', 'Stalemate');
                eventString = 'DS';
            }
            return eventString;
        }
        /*
         * If control reaches here, it means the active player has at least one legal move.
         * This block checks for any "after my move" draw claims, and if said claim is accurate.
         * If they did, this block ends the game under the appropriate result detail and returns from the function.
         * This block has to come after the block checking for legal moves by the active player- otherwise, a draw claim could supersede a checkmate.
         */
        if (claim != null) {
            if ((claim == '3 Time Repetition' && check3xRep(gameid))) {
                eventString = 'D3';
            } else if (check50MoveRule(gameid)) {
                eventString = 'D50';
            }
            if (eventString != '') {
                setResult(gameid, '.5-.5', claim);
                return eventString;
            } else {
                game.Claim_Type__c = '';
                update game;
            }
        }
        /*
         * If control reaches here, it means:
         *     1. Either there was no draw claim to evaluate, or the claim turned out to be false, AND
         *     2. The active player has at least one legal move.
         * So there's only one way left for the game to be over if control reaches here- insufficient material for checkmate.
         */
        if (sufficient) {
            return '';
        }
        /*
         * If control reaches here, it means:
         * 		1. The active player by him/herself doesn't have sufficient material for checkmate, AND
         *      2. Either there was no draw claim to evaluate, or the claim turned out to be false, AND
         * 		3. The active player has at least one valid move.
         * So the last thing to do is probe for insufficient material by looking at what's left of the opposing player's material, which this structure does.
         * Note that whitebishop, blackbishop, and knight, are intentionally not reset.
         *      This is because checkmate can still be possible if neither player has sufficient material to checkmate a lone king.
         *      This can happen by having one side's extra piece block the king into checkmate.
         *      This scenario is, of course, highly unlikely. But this program is designed to call it sufficient until checkmate isn't even theoretically possible.
		 */
        for (Game_Piece__c enemy: enemyMaterial) {
            switch on enemy.Piece_Type__c {
                when 'Queen' {
                    sufficient = true;
                } when 'Rook' {
                    sufficient = true;
                } when 'Pawn' {
                    sufficient = true;
                } when 'Knight' {
                    if (knight || blackbishop || whitebishop) {
                        sufficient = true;
                    } else {
                        knight = true;
                    }
                } when 'Bishop' {
                    Game_Square__c enemySquare = squareMap.get(enemy.Current_Location__c);
                    if (!blackbishop && enemySquare.Color__c == 'Black') {
                        blackbishop = true;
                    }
                    if (!whitebishop && enemySquare.Color__c == 'White') {
                        whitebishop = true;
                    }
                    bothbishops = (whitebishop && blackbishop);
                    if (bothbishops || knight) {
                        sufficient = true;
                    }
            	}
        	}
            if (sufficient) {
                return '';
            }
        }
        /*
         * If control reaches here, it means there's insufficient material for checkmate on the board.
         */
        setResult(gameid, '.5-.5', 'Insufficient Material');
        eventString = 'DI';
        return eventString;
    }
    
    /*
     * Set the game result to the appropriate player winning, and announce a corresponding global event.
     */
    @AuraEnabled
    public static boolean auraResign(ID gameid, ID userid) {
        Game__c game = getGame(gameid);
        Set<ID> players = new Set<ID>{game.White_Player__c, game.Black_Player__c};
        if (players.contains(userid)) {
            boolean blackWin = userid==game.White_Player__c; //if this seems backwards, it's because the player resigning is not the player that wins.
            String eventString = 'W' + (blackWin?'B':'W') + 'R';
            setResult(gameid, (blackWin)?'0-1':'1-0', 'Resignation');
            Chess_Piece_Move__e winEvent = new Chess_Piece_Move__e(Squares__c=eventString, Game_Number__c=Integer.valueOf(game.Game_Number__c));
            Database.SaveResult eventResult = EventBus.publish(winEvent);
            System.debug('Publish: ');
            System.debug(eventResult.isSuccess());
            return true;
        } else {
            return false;
        }
    }
    
    @AuraEnabled
    public static boolean auraOfferOrAcceptDraw(ID gameid, ID userid) {
        Game__c game = getGame(gameid);
        ID priorOffer = game.Active_Draw_Offer__c;
        Set<ID> players = new Set<ID>{game.White_Player__c, game.Black_Player__c};
        //validate that the one offering the draw is a player of the game.
        if (players.contains(userid)) {
            String eventString;
            /*
             * If one player offered the draw and the other accepted it.
             * It doesn't matter which side offered and which accepted.
             */
            if (players == (new Set<ID>{userid, priorOffer})) {
                game.Result__c = '.5-.5';
                game.Result_Detail__c = 'Agreement';
                game.Active_Draw_Offer__c = null;
                eventString = 'DA'; //short for draw by agreement
            } else {
                game.Active_Draw_Offer__c = userid;
                eventString = userid==game.White_Player__c?'OW':'OB'; //offer by white or offer by black
            }
            Chess_Piece_Move__e drawEvent = new Chess_Piece_Move__e(Squares__c=eventString, Game_Number__c=Integer.valueOf(game.Game_Number__c));
            Database.SaveResult eventResult = EventBus.publish(drawEvent);
            System.debug('Publish: ');
            System.debug(eventResult.isSuccess());
            update game;
            return true;
        } else {
            return false;
        }
    }
    
    /*
     * There are two types rationales for claiming a draw: 3 time repetition and 50 move rule
     *     The argument "is3xRep" tells which it is.
     * Moreover, a draw claim can only be made during the claimant's turn.
     *     For this reason, a draw can be claimed "now" or "after my move".
     *     The "now" claim checks the condition immediately.
     *     The "after my move" claim waits for the player's move, then checks the position that the opponent would be in.
     *     The argument "isNow" conveys which it is.
     * If a draw claim is incorrect it's converted to a draw offer.
     * If the claim is "after my move", it is also a draw offer that the other player can accept, but the claim condition also gets checked after the player to move makes a move.
     */
    @AuraEnabled
    public static boolean auraClaimDraw(ID gameid, ID userid, boolean is3xRep, boolean isNow) {
        initdata(gameid);
        Game__c game = getGame(gameid);
        game.Last_Draw_Claim__c = game.Finished_Moves__c;
        update game;
        ID toMove = game.Player_To_Move__c=='White'?game.White_Player__c:game.Black_Player__c;
        if (toMove != userid) {
            return false;
        }
        if (isNow) {
            //Check if the claim is correct. If it is, make the game a draw.
            if (is3xRep) {
                boolean correct = check3xRep(gameid);
                if (correct) {
                    setResult(gameid, '.5-.5', '3 Time Repetition');
                    Chess_Piece_Move__e drawEvent = new Chess_Piece_Move__e(Squares__c='D3', Game_Number__c=Integer.valueOf(game.Game_Number__c));
            		Database.SaveResult eventResult = EventBus.publish(drawEvent);
                } else {
                    auraOfferOrAcceptDraw(gameid, userid);
                }
            } else {
                if (check50MoveRule(gameid)) {
                    setResult(gameid, '.5-.5', '50 Move Rule');
                    Chess_Piece_Move__e drawEvent = new Chess_Piece_Move__e(Squares__c='D50', Game_Number__c=Integer.valueOf(game.Game_Number__c));
            		Database.SaveResult eventResult = EventBus.publish(drawEvent);
                } else {
                    auraOfferOrAcceptDraw(gameid, userid);
                }
            }
        } else {
            //Set the claim to be checked next time 'calculateFinality' is called.
            String claimType = is3xRep?'3 Time Repetition':'50 Move Rule';
            auraOfferOrAcceptDraw(gameid, userid);
            game.Claim_Type__c = claimType;
            update game;
        }
        return true;
    }
    
    /*
     * If a player makes a claim of a 3 time repetition, the game checks whether that claim is true.
     * For the claim to be true, the current position must be identical to at least two prior positions (total of 3 times).
     * Requirements for positions to be identical:
     *     Same type of piece of the same color on each square.
     *         It does not matter if two identical pieces switched places. If two positions look identical but two white knights switched places, the position is still identical.
     *         For a 3 time repetition, all 3 iterations of the position must happen before the last pawn move or capture.**
     *     Same player's turn.
     *     Same set of remaining castling rights. This one is tricky:
     *         It doesn't matter whether castling is possible in this particular position- only whether future castling is possible for a given player.
     *         As such, for this check, it doesn't look at whether this particular position allows for castling, only whether the corresponding pieces have moved.
     *         So the way it's implemented, each player starts the game with two rights to castle- the kingside castling right, and the queenside castling right.
     *         Each right to castle is lost the first time one of the pieces involved moves.
     *         If the set of castling rights changed between two positions, they cannot be identical.
     *         For a 3 time repetition, all 3 iterations of the position must happen before the most recent loss of castling rights.**
     *     Same set of en passant rights. This one does not behave like the castling rights requirement.
     *         Unlike for castling, this requirement only accounts for if en passant is legal right now, in this particular position.
     *         If it's the correct turn for an en passant but the move would expose the king, it's the same as if it's not the correct turn, at least for position identicality.
     *         Any position where en passant is legal cannot be used in a 3 time repetition.**
     * Any rule marked with ** isn't a written rule, but a logical consequence of other written rules (and is as good as a rule).
     */
    public static boolean check3xRep(ID gameid) {
        String position = null;
        integer moves = 0;
        integer repetitions = 0;
        boolean whiteToMove = Math.mod(history.size(), 2)==0;
        for (Move__c move: history) {
            if (move.Captured__c != null || move.Piece__r.Piece_Type__c == 'Pawn') {
                return false;
            }
            if (position == null) {
                position = move.End_Position__c;
            } else if ((whiteToMove == (Math.mod(move.Move_Number__c.intValue(),2) == 1)) && (position == move.End_Position__c)) {
                repetitions += 1;
                //2 because repetitions isn't incremented for the current move
                if (repetitions == 2) {
                    return true;
                }
            }
            /*
             * The position before a move is only recorded in the prior move.
             * This means the starting position is never recorded
             * So if the starting position gets repeated 3 times, the loop would normally only catch 2 repetitions of it
             * If that happens, this statement triggers and catches the third repetition of it.
             */
            if (move.Move_Number__c == 1 && repetitions == 1 && whiteToMove && position == 'RNBQKBNRPPPPPPPP--------------------------------pppppppprnbqkbnrF-') {
                return true;
            }
        }
        return false;
    }

    /*
     * If a player makes a claim of a draw by the 50 move rule, the game has to check whether that's true.
     * For this to be true:
     *     1. Both players must have made at least 50 moves.
     *     2. The most recent 50 of both player's moves must not contain a pawn move or capture.
     * Unlike for 3 time repetition, a change in the castling rights does not reset the 50 move clock.
     */
    public static boolean check50MoveRule(ID gameid) {
        integer moves = 0;
        for (Move__c move: history) {
            if (move.Captured__c != null || move.Piece__r.Piece_Type__c == 'Pawn') {
                return false;
            }
            moves += 1;
            //100 because it's 50 for each side
            if (moves >= 100) {
                return true;
            }
        }
        return false;
    }
    
    public static void setResult(ID gameid, String result, String resultDetail) {
        Game__c game = getGame(gameid);
        game.Result__c = result;
        game.Result_Detail__c = resultDetail;
        game.Active_Draw_Offer__c = null;
        game.Claim_Type__c = '';
        update game;
    }
    
    @AuraEnabled
    public static ID checkOffer(ID gameid) {
        Game__c game = getGame(gameid);
        return game.Active_Draw_Offer__c;
    }
}