import 'package:flutter/material.dart';

class WelcomeSlideData {
  final String title;
  final String body;
  final IconData icon;
  final Color? iconColor;

  const WelcomeSlideData({
    required this.title,
    required this.body,
    required this.icon,
    this.iconColor,
  });

  static const List<WelcomeSlideData> slides = [
    WelcomeSlideData(
      title: 'Welcome to ScheduleHQ',
      body: 'Your all-in-one workforce scheduling and PTO management tool. '
          'This quick guide will walk you through the essentials to get your team up and running.',
      icon: Icons.calendar_month,
    ),
    WelcomeSlideData(
      title: 'Configure Your Store',
      body: 'Start by heading to Settings to set up your store name, operating hours, '
          'job codes, PTO rules, and shift templates. This is the foundation for everything else.',
      icon: Icons.settings,
    ),
    WelcomeSlideData(
      title: 'Build Your Team',
      body: 'Next, go to the Roster page to add your employees. Assign job codes, '
          'set vacation allowances, and configure weekly templates for each team member.',
      icon: Icons.people,
    ),
    WelcomeSlideData(
      title: 'Create Schedules',
      body: 'With your store configured and team added, head to the Schedule page '
          'to start building weekly schedules. Click cells to assign shifts quickly.',
      icon: Icons.event_note,
    ),
    WelcomeSlideData(
      title: 'Need Help Later?',
      body: 'You can re-launch this guide anytime from the "Getting Started" button '
          'in the sidebar. We\'ll also highlight key features as you visit each page for the first time.',
      icon: Icons.help_outline,
    ),
  ];
}
