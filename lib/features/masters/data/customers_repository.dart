import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/paginate.dart';
import '../../../shared/models/customer.dart';

class CustomersRepository {
  CustomersRepository(this._api);
  final ApiClient _api;

  Future<List<Customer>> list({String? query}) async {
    final rows = await fetchAllPages(
      _api,
      '/customers',
      query: {if (query != null && query.isNotEmpty) 'q': query},
    );
    return rows.map(Customer.fromJson).toList();
  }

  Future<Customer> create(Customer c) async {
    final res = await _api.dio.post('/customers', data: c.toJson());
    return Customer.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<Customer> update(Customer c) async {
    final res = await _api.dio.patch(
      '/customers/${c.id}',
      data: c.toJson(),
      options: Options(headers: {'If-Match': c.version.toString()}),
    );
    return Customer.fromJson((res.data['data'] as Map).cast<String, dynamic>());
  }

  Future<void> remove(String id) async {
    await _api.dio.delete('/customers/$id');
  }
}
