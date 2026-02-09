import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';

class PtoRulesTab extends StatefulWidget {
  const PtoRulesTab({super.key});

  @override
  State<PtoRulesTab> createState() => _PtoRulesTabState();
}

class _PtoRulesTabState extends State<PtoRulesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error?.isNotEmpty ?? false) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Error: ${provider.error}'),
                ElevatedButton(
                  onPressed: () => provider.loadData(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final settings = provider.settings;
        if (settings == null) {
          return const Center(child: Text('No settings available'));
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              const Text("PTO Rules", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              TextField(
                decoration: const InputDecoration(labelText: "PTO Hours Per Trimester"),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: settings.ptoHoursPerTrimester.toString()),
                onChanged: (v) {
                  final value = int.tryParse(v) ?? 0;
                  provider.updateSettings(ptoHoursPerTrimester: value);
                },
              ),

              TextField(
                decoration: const InputDecoration(labelText: "Max Carryover Hours"),
                keyboardType: TextInputType.number,
                controller: TextEditingController(text: settings.maxCarryoverHours.toString()),
                onChanged: (v) {
                  final value = int.tryParse(v) ?? 0;
                  provider.updateSettings(maxCarryoverHours: value);
                },
              ),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => provider.refresh(),
                child: const Text("Save PTO Settings"),
              ),
            ],
          ),
        );
      },
    );
  }
}
