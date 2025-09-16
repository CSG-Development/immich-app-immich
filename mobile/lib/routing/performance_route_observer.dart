import 'package:auto_route/auto_route.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/services/firebase_performance_wrapper.dart';

class PerformanceRouteObserver extends AutoRouterObserver {
  final Map<String, Trace> _traces = {};

  @override
  void didInitTabRoute(TabPageRoute route, TabPageRoute? previousRoute) {
    super.didInitTabRoute(route, previousRoute);
    final currentName = route.name;
    
    final currentTabName = currentName.replaceAll('Route', '');
    if (!_traces.containsKey(currentTabName)) {
      final trace = FirebasePerformanceWrapper.newTrace('screen_$currentTabName') ?? NoOpTrace();
      trace.start();
      _traces[currentTabName] = trace;
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    
    // Special handling for SearchRoute
    if (route.settings.name == 'SearchRoute') {
      final trace = FirebasePerformanceWrapper.newTrace('screen_Search') ?? NoOpTrace();
      trace.start();
      _traces['Search'] = trace;
      return;
    }
    
    _startTrace(route);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    
    // Special handling for SearchRoute
    if (route.settings.name == 'SearchRoute') {
      final trace = _traces['Search'];
      if (trace != null) {
        trace.stop();
        _traces.remove('Search');
      }
      return;
    }
    
    _stopTrace(route);
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    
    // Special handling for SearchRoute
    if (oldRoute?.settings.name == 'SearchRoute') {
      final trace = _traces['Search'];
      if (trace != null) {
        trace.stop();
        _traces.remove('Search');
      }
    }
    if (newRoute?.settings.name == 'SearchRoute') {
      final trace = FirebasePerformanceWrapper.newTrace('screen_Search') ?? NoOpTrace();
      trace.start();
      _traces['Search'] = trace;
      return;
    }
    
    if (oldRoute != null) _stopTrace(oldRoute);
    if (newRoute != null) _startTrace(newRoute);
  }

  @override
  void didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) {
    super.didChangeTabRoute(route, previousRoute);
    final previousName = previousRoute.name;
    final currentName = route.name;

    // Handle tab route names
    final previousTabName = previousName.replaceAll('Route', '');
    final currentTabName = currentName.replaceAll('Route', '');
    
    final trace = _traces[previousTabName];
    if (trace != null) {
      trace.stop();
      _traces.remove(previousTabName);
    }
    if (!_traces.containsKey(currentTabName)) {
      final trace = FirebasePerformanceWrapper.newTrace('screen_$currentTabName') ?? NoOpTrace();
      trace.start();
      _traces[currentTabName] = trace;
    }
  }

  void _startTrace(Route route) {
    final routeName = route.settings.name;
    if (routeName != null && !_traces.containsKey(routeName)) {
      final trace = FirebasePerformanceWrapper.newTrace('screen_$routeName') ?? NoOpTrace();
      trace.start();
      _traces[routeName] = trace;
    }
  }

  void _stopTrace(Route route) {
    final routeName = route.settings.name;
    if (routeName != null && _traces.containsKey(routeName)) {
      final trace = _traces[routeName]!;
      trace.stop();
      _traces.remove(routeName);
    }
  }
}