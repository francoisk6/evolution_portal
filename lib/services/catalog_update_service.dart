import '../data/models/catalog_update.dart';
import 'api_service.dart';

class CatalogUpdateService {
  CatalogUpdateService._();
  static final CatalogUpdateService instance = CatalogUpdateService._();

  Future<CatalogUpdateResult> run(CatalogTarget target) async {
    final m = await ApiService.instance.runCatalogUpdate(
      key: target.key,
      timeout: target.timeout,
    );
    return CatalogUpdateResult.fromJson(m);
  }
}
