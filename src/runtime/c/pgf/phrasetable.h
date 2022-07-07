#ifndef PHRASETABLE_H
#define PHRASETABLE_H

struct PgfSequence;
struct PgfSequenceBackref;

struct PGF_INTERNAL_DECL PgfPhrasetableEntry {
    ref<PgfSequence> seq;
    ref<Vector<PgfSequenceBackref>> backrefs;
};

class PgfSequenceItor;
typedef ref<Node<PgfPhrasetableEntry>> PgfPhrasetable;

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wattributes"

struct PgfPhrasetableIds {
public:
	PGF_INTERNAL_DECL PgfPhrasetableIds();
	PGF_INTERNAL_DECL ~PgfPhrasetableIds() { end(); }

	PGF_INTERNAL_DECL void start(ref<PgfConcr> concr);
	PGF_INTERNAL_DECL size_t add(ref<PgfSequence> seq);
	PGF_INTERNAL_DECL size_t get(ref<PgfSequence> seq);
	PGF_INTERNAL_DECL void end();

private:
	size_t next_id;

	struct PGF_INTERNAL_DECL SeqIdChain;

	struct PGF_INTERNAL_DECL SeqIdPair {
		SeqIdChain *chain;
		ref<PgfSequence> seq;
		size_t seq_id;
	};

	struct PGF_INTERNAL_DECL SeqIdChain : public SeqIdPair {
		SeqIdChain *next;
	};

	size_t n_pairs;
	SeqIdPair  *pairs;
	SeqIdChain *chains;
};

#pragma GCC diagnostic pop

PGF_INTERNAL_DECL
PgfPhrasetable phrasetable_internalize(PgfPhrasetable table,
                                       ref<PgfSequence> seq,
                                       object container,
                                       size_t seq_index,
                                       ref<PgfPhrasetableEntry> *pentry);

PGF_INTERNAL_DECL
ref<PgfSequence> phrasetable_relink(PgfPhrasetable table,
                                    object container,
                                    size_t seq_index,
                                    size_t seq_id);

PgfPhrasetable phrasetable_delete(PgfPhrasetable table,
                                  object container,
                                  size_t seq_index,
                                  ref<PgfSequence> seq);

PGF_INTERNAL_DECL
size_t phrasetable_size(PgfPhrasetable table);

typedef struct {
	size_t pos;            // position in Unicode characters
	const uint8_t *begin;  // pointer into the beginning of the range
	const uint8_t *end;    // pointer into the end of the range
} PgfTextRange;

PGF_INTERNAL_DECL
void phrasetable_lookup(PgfPhrasetable table,
                        PgfTextRange *sentence,
                        bool case_sensitive,
                        Namespace<struct PgfConcrLincat> lincats,
                        PgfMorphoCallback* callback, PgfExn* err);

PGF_INTERNAL_DECL
void phrasetable_lookup_prefixes(PgfPhrasetable table,
                                 PgfTextRange *sentence,
                                 bool case_sensitive,
                                 Namespace<PgfConcrLincat> lincats,
                                 ptrdiff_t min, ptrdiff_t max,
                                 PgfCohortsCallback* callback, PgfExn* err);

PGF_INTERNAL_DECL
void phrasetable_iter(PgfConcr *concr,
                      PgfPhrasetable table,
                      PgfSequenceItor* itor,
                      PgfMorphoCallback *callback,
                      PgfPhrasetableIds *seq_ids, PgfExn *err);

PGF_INTERNAL_DECL
void phrasetable_release(PgfPhrasetable table);

#endif
