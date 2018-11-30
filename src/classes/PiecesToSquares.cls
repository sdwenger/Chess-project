public class PiecesToSquares {
	@InvocableMethod
    public static void link(List<Game_Square__c> records) {
        Set<ID> games = new Set<ID>();
        for (Game_Square__c square: records) {
            games.add(square.Game__c);
        }
        List<Game_Piece__c> rawPieces = [SELECT ID, Game__r.Game_Number__c, Piece__r.Initial_Location__r.Name FROM Game_Piece__c WHERE Game__c IN :games];
        List<Game_Square__c> rawSquares = [SELECT ID, Game__r.Game_Number__c, Square__r.Name FROM Game_Square__c WHERE Game__c IN :games];
        Map<String, Game_Piece__c> pieces = new Map<String, Game_Piece__c>();
        for (Game_Piece__c piece: rawPieces) {
            String locator = piece.Game__r.Game_Number__c + piece.Piece__r.Initial_Location__r.Name;
            pieces.put(locator, piece);
        }
        rawPieces = new List<Game_Piece__c>();
        for (Game_Square__c square: rawSquares) {
            String locator = square.Game__r.Game_Number__c + square.Square__r.Name;
            Game_Piece__c piece = pieces.get(locator);
            //this block executes if the square isn't initially empty
            if (piece != null) {
                square.Current_Occupant__c = piece.ID;
                piece.Current_Location__c = square.ID;
            	rawPieces.add(piece);
            }
        }
        update rawPieces;
        update rawSquares;
    }
}