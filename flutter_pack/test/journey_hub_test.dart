import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/auth_service.dart';
import '../lib/journey_hub.dart';

class FakeAuth extends AuthService {
  FakeAuth():super(null);
  @override bool get remote=>true;
  @override Future<Json> api(String method,String path,[Json? body]) async {
    if(path=='/catalog')return {
      'demoDeparture':DateTime.now().add(const Duration(days:1)).millisecondsSinceEpoch/1000,
      'stops':[{'id':1,'name':'Aktobe Central'},{'id':4,'name':'Khromtau Centre'}],
    };
    if(path=='/search')return {'options':<Json>[],'message':'No suitable service. Required needs retained.'};
    return {};
  }
}
void main(){
  testWidgets('Core search remains scrollable at 360x800 and 200% text', (tester) async {
    tester.view.physicalSize=const Size(360,800);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final auth=FakeAuth();addTearDown(auth.close);
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(
      data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(2)),child:child!),
      home:JourneyHub(store:null,sharedAuth:auth)));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
    await tester.ensureVisible(find.text('Find journeys'));
    await tester.tap(find.text('Find journeys'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No matching journey'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('Checkout requires traveller fields before reserving', (tester) async {
    final auth=FakeAuth();addTearDown(auth.close);
    await tester.pumpWidget(MaterialApp(home:CheckoutPage(auth:auth,words:const Words('en'),option:{
      'legs':<Json>[],'query':{'passengers':1},'totalCents':35000,
    })));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reserve for 5 minutes'));
    await tester.tap(find.text('Reserve for 5 minutes'));
    await tester.pump();
    expect(find.text('Enter traveller name and valid contact email.'),findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
