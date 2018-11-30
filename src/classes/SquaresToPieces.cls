public class SquaresToPieces {
	@InvocableMethod
    public static void link(List<Game_Piece__c> records) {
		Set<ID> games = new Set<ID>();
        for (Game_Piece__c piece: records) {
            games.add(piece.Game__c);
        }
        List<Game_Piece__c> rawPieces = [SELECT ID, Game__r.Game_Number__c, Piece__r.Initial_Location__r.Name FROM Game_Piece__c WHERE Game__c IN :games];
        List<Game_Square__c> rawSquares = [SELECT ID, Game__r.Game_Number__c, Square__r.Name FROM Game_Square__c WHERE Game__c IN :games];
        Map<String, Game_Square__c> squares = new Map<String, Game_Square__c>();
        for (Game_Square__c square: rawSquares) {
            String locator = square.Game__r.Game_Number__c + square.Square__r.Name;
            System.debug(locator);
            squares.put(locator, square);
        }
        rawSquares = new List<Game_Square__c>();
        for (Game_Piece__c piece: rawPieces) {
            String locator = piece.Game__r.Game_Number__c + piece.Piece__r.Initial_Location__r.Name;
            System.debug(locator);
            Game_Square__c square = squares.get(locator);
            if (square != null) {
                square.Current_Occupant__c = piece.ID;
                piece.Current_Location__c = square.ID;
                rawSquares.add(square);
            }
        }
        update rawPieces;
        update rawSquares;
    }
}