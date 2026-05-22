import '../../shared/models/consignee.dart';
import '../../shared/models/consignor.dart';
import '../../shared/models/driver.dart';
import '../../shared/models/lr_models.dart';
import '../../shared/models/route_master.dart';
import '../../shared/models/transporter.dart';
import '../../shared/models/user.dart';
import '../../shared/models/vehicle.dart';

class MockData {
  MockData._();

  static const consignors = <Consignor>[
    Consignor(
      id: 'CN001',
      name: 'LUMINAZ SAFETY GLASS',
      gst: '27AABCL1234M1Z5',
      city: 'Pune',
      address: 'Plot 14, MIDC Bhosari, Pune 411026',
      contact: 'R. Kale',
      mobile: '98220 11223',
      email: 'dispatch@luminaz.in',
    ),
    Consignor(
      id: 'CN002',
      name: 'SHREE BALAJI POLYMERS',
      gst: '27AAACS5678N1Z3',
      city: 'Mumbai',
      address: 'Unit 7, Andheri MIDC, Mumbai 400093',
      contact: 'S. Mehta',
      mobile: '98330 44556',
      email: 'ops@balajipoly.com',
    ),
    Consignor(
      id: 'CN003',
      name: 'KARAD AGRO FOODS',
      gst: '27AAFCK9012P1Z8',
      city: 'Karad',
      address: 'Plot D-22, MIDC Karad, Satara 415110',
      contact: 'Y. Patil',
      mobile: '94220 77889',
      email: 'plant@karadagro.in',
    ),
  ];

  static const consignees = <Consignee>[
    Consignee(
      id: 'CE001',
      name: 'TATA AUTOCOMP SYSTEMS',
      gst: '27AAACT3456Q1Z2',
      location: 'Chakan, Pune',
      address: 'Gate 3, Chakan Industrial Area',
      contact: 'P. Joshi',
      mobile: '98900 12345',
    ),
    Consignee(
      id: 'CE002',
      name: 'BAJAJ AUTO LTD',
      gst: '27AAACB7890R1Z9',
      location: 'Waluj, Aurangabad',
      address: 'Waluj MIDC, Aurangabad',
      contact: 'M. Shaikh',
      mobile: '97660 55443',
    ),
    Consignee(
      id: 'CE003',
      name: 'RELIANCE RETAIL DC',
      gst: '27AAACR2345S1Z6',
      location: 'Bhiwandi, Thane',
      address: 'Logistics Park, Bhiwandi',
      contact: 'A. Nair',
      mobile: '98201 99887',
    ),
  ];

  static const vehicles = <Vehicle>[
    Vehicle(
      id: 'V001',
      number: 'MH12 AB 4567',
      type: 'Truck',
      capacity: '10MT 22FT',
      driver: 'Ramesh Pawar',
      driverMobile: '90110 23344',
      mode: 'Road',
      pmark: 'P-22',
    ),
    Vehicle(
      id: 'V002',
      number: 'MH14 CD 8899',
      type: 'Container',
      capacity: '20MT 32FT',
      driver: 'Sunil More',
      driverMobile: '90220 56677',
      mode: 'Road',
      pmark: 'P-32',
    ),
    Vehicle(
      id: 'V003',
      number: 'MH09 EF 1212',
      type: 'Open Body',
      capacity: '9MT 19FT',
      driver: 'Imran Sheikh',
      driverMobile: '90330 88990',
      mode: 'Road',
      pmark: 'P-19',
    ),
    Vehicle(
      id: 'V004',
      number: 'MH04 GH 3434',
      type: 'Trailer',
      capacity: '25MT 40FT',
      driver: 'Vijay Salunke',
      driverMobile: '90440 11223',
      mode: 'Road',
      pmark: 'P-40',
    ),
  ];

  static const drivers = <Driver>[
    Driver(
      id: 'DR001',
      name: 'Ramesh Pawar',
      mobile: '90110 23344',
      licenseNo: 'MH12 20180012345',
      licenseExpiry: '2028-04-12',
      address: 'Bhosari, Pune',
    ),
    Driver(
      id: 'DR002',
      name: 'Sunil More',
      mobile: '90220 56677',
      licenseNo: 'MH14 20190045678',
      licenseExpiry: '2029-02-20',
      address: 'Hadapsar, Pune',
    ),
    Driver(
      id: 'DR003',
      name: 'Imran Sheikh',
      mobile: '90330 88990',
      licenseNo: 'MH09 20200078912',
      licenseExpiry: '2026-09-05',
      address: 'Kolhapur',
    ),
    Driver(
      id: 'DR004',
      name: 'Vijay Salunke',
      mobile: '90440 11223',
      licenseNo: 'MH04 20170023445',
      licenseExpiry: '2027-07-19',
      address: 'Karad, Satara',
    ),
  ];

  static const routeMasters = <RouteMaster>[
    RouteMaster(
        id: 'RT001',
        fromCity: 'Pune',
        toCity: 'Chakan',
        distanceKm: 32,
        baseRate: 4500),
    RouteMaster(
        id: 'RT002',
        fromCity: 'Pune',
        toCity: 'Mumbai',
        distanceKm: 150,
        baseRate: 12500),
    RouteMaster(
        id: 'RT003',
        fromCity: 'Karad',
        toCity: 'Pune',
        distanceKm: 165,
        baseRate: 13500),
    RouteMaster(
        id: 'RT004',
        fromCity: 'Mumbai',
        toCity: 'Aurangabad',
        distanceKm: 335,
        baseRate: 22500),
    RouteMaster(
        id: 'RT005',
        fromCity: 'Pune',
        toCity: 'Bhiwandi',
        distanceKm: 140,
        baseRate: 11500),
  ];

  static const transporters = <Transporter>[
    Transporter(
        id: 'TR1', name: 'Vistar Own Fleet', pan: 'AABCV1234M', tds: 'Yes'),
    Transporter(
        id: 'TR2', name: 'Sai Roadlines', pan: 'AAFPS5678K', tds: 'No'),
    Transporter(
        id: 'TR3',
        name: 'Maratha Carriers',
        pan: 'ABLPM9012J',
        tds: 'Yes'),
  ];

  static const routes = <String>[
    'Pune → Chakan',
    'Pune → Mumbai',
    'Karad → Pune',
    'Mumbai → Aurangabad',
    'Pune → Bhiwandi',
  ];

  static const vehicleTypes = <String>[
    'Truck',
    'Container',
    'Open Body',
    'Trailer',
  ];

  static const packageTypes = <String>['Pallet', 'Box', 'Carton', 'Bag'];

  static const users = <AppUser>[
    AppUser(
        username: 'admin',
        password: 'admin',
        role: UserRole.admin,
        name: 'Yash Patil'),
    AppUser(
        username: 'anita',
        password: 'anita',
        role: UserRole.operator,
        name: 'Anita Deshmukh'),
    AppUser(
        username: 'ravi',
        password: 'ravi',
        role: UserRole.accounts,
        name: 'Ravi Kulkarni'),
  ];

  static List<LorryReceipt> seedLrs() {
    final list = <LorryReceipt>[];
    for (var i = 0; i < 14; i++) {
      final cons = consignors[i % consignors.length];
      final cnee = consignees[i % consignees.length];
      final veh = vehicles[i % vehicles.length];
      final tr = transporters[i % transporters.length];
      final freightAmt = (8000 + (i % 7) * 1450).toDouble();
      final door = ((i % 3) * 500).toDouble();
      final handling = (300 + (i % 4) * 150).toDouble();
      final gst = ((freightAmt + door + handling) * 0.12).roundToDouble();
      final advance = ((i % 2) * 2000).toDouble();
      final route = routes[i % routes.length];
      final parts = route.split(' → ');
      final date = DateTime(2025, 11, 20 - i);
      final status = i % 4 == 0
          ? LrStatus.delivered
          : (i % 4 == 1
              ? LrStatus.inTransit
              : (i % 4 == 2 ? LrStatus.booked : LrStatus.inTransit));
      final pay = i % 3 == 0
          ? PayType.tbb
          : (i % 3 == 1 ? PayType.toPay : PayType.paid);

      final item = InvoiceItem(
        invoiceNo: 'INV/${1000 + i}',
        invoiceDate: date,
        asn: 'ASN${5000 + i}',
        partDescription: 'Auto components batch ${i + 1}',
        quantity: 50 + (i % 6) * 12,
        weight: 1200 + (i % 5) * 350.0,
        grossValue: 250000 + (i % 7) * 18500.0,
        packages: 12 + (i % 6) * 4,
        packageType: i % 2 == 0 ? 'Pallet' : 'Box',
        natureOfGoods: 'Industrial Goods',
      );

      list.add(
        LorryReceipt(
          id: 'LR$i',
          number:
              'VLL/25/${date.month.toString().padLeft(2, '0')}/${(56 + i).toString().padLeft(5, '0')}',
          date: date,
          enteredBy: i % 2 == 0 ? 'anita' : 'admin',
          consignor: cons,
          consignee: cnee,
          vehicle: veh,
          transporter: tr,
          route: route,
          fromCity: parts[0],
          toCity: parts.length > 1 ? parts[1] : parts[0],
          items: [item],
          freight: FreightDetails(
            freight: freightAmt,
            doorDelivery: door,
            handling: handling,
            gst: gst,
            advance: advance,
            mathadi: (i % 4) * 350.0,
            vistarMargin: 1500 + (i % 5) * 400.0,
            advancePaidBy: const ['Vistar', 'Customer', 'Vistar'][i % 3],
            tripLeadBy: const ['Operations', 'Sales', 'Operations'][i % 3],
          ),
          ewb: EwayBill(
            number: '${901234567890 + i}',
            expiry: date.add(const Duration(days: 7)),
            loadType: 'Full Load',
          ),
          payType: pay,
          deliveryType: DeliveryType.values[i % DeliveryType.values.length],
          status: status,
          remarks: null,
        ),
      );
    }
    return list;
  }
}
