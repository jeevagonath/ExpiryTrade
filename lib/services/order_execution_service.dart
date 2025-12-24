import 'shoonya_api_client.dart';

class OrderExecutionService {
  final ShoonyaApiClient apiClient;

  OrderExecutionService(this.apiClient);

  Future<void> squareOffPosition(dynamic pos) async {
    try {
      final double netQty = double.tryParse(pos['netqty']?.toString() ?? '0') ?? 0;
      if (netQty == 0) return;

      final transactionType = netQty > 0 ? 'S' : 'B';
      final qtyToExit = netQty.abs().toInt().toString();

      print('Squaring off ${pos['tsym']}: $qtyToExit shares ($transactionType)');

      await apiClient.placeOrder(
        exchange: pos['exch'],
        tradingSymbol: pos['tsym'],
        quantity: qtyToExit,
        price: '0', // Market
        product: pos['prd'],
        transactionType: transactionType,
        priceType: 'MKT',
        retention: 'DAY',
        remarks: 'Manual Square-off',
      );
    } catch (e) {
      print('Error in squareOffPosition: $e');
      rethrow;
    }
  }

  Future<void> squareOffAllPositions() async {
    try {
      final positions = await apiClient.getPositionBook();
      if (positions.isEmpty) {
        print('No positions to square off.');
        return;
      }

      for (var pos in positions) {
        await squareOffPosition(pos);
      }
    } catch (e) {
      print('Error in squareOffAllPositions: $e');
      rethrow;
    }
  }
}
